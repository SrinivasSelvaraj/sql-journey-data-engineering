---
date: 2026-10-13
phase: pipelines
topic: dbt parse and manifest: understanding DAG metadata
---

# dbt parse and manifest: understanding DAG metadata

*Pipelines and orchestration*

## Concept

The dbt parse step reads your project's YAML and SQL files and builds a Directed Acyclic Graph (DAG) stored in `manifest.json`. This manifest contains metadata about every model, test, macro, and dependency—the blueprint of your entire transformation pipeline. Without it, dbt cannot determine execution order, detect circular dependencies, or know which tests belong to which models.

The manifest is critical for orchestration and debugging. When a model fails, you need the DAG to understand what depends on it and what might cascade. When you add a new model, the manifest tells your scheduler (Airflow, dbt Cloud, etc.) exactly how to wire it in. If parsing fails—malformed YAML, undefined `ref()` calls, or broken macros—your entire pipeline stalls because dbt cannot build the graph.

Parse errors often surface issues that would otherwise hide: a model referencing a table that doesn't exist, a cyclic dependency, or a test configured on a model that was deleted. This is why "fail loudly" starts here—parse failures force you to fix problems before they corrupt production.

## Practice

**Problem:** You have a fact table `job_postings_fact` and you want to ensure that salary values are realistic (between $30k and $500k annually) and that no posting is recorded with a future date. You also need to validate that `job_work_from_home` is never null. Write the models and tests so that the manifest correctly tracks these dependencies.

```sql
-- models/staging/stg_job_postings.sql
{{ config(materialized='table') }}

SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM {{ source('raw', 'job_postings_raw') }}
WHERE job_posted_date <= CURRENT_DATE

-- models/marts/job_postings_fact.sql
{{ config(materialized='table') }}

SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM {{ ref('stg_job_postings') }}

-- models/marts/job_postings_fact.yml
version: 2
models:
  - name: job_postings_fact
    description: Fact table of job postings with validated salary and date ranges
    columns:
      - name: job_id
        description: Primary key
        tests:
          - unique
          - not_null
      - name: salary_year_avg
        tests:
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 30000
              max_value: 500000
      - name: job_posted_date
        tests:
          - dbt_utils.not_null_where:
              where: "job_posted_date > CURRENT_DATE"
      - name: job_work_from_home
        tests:
          - not_null
```

When you run `dbt parse`, the manifest records that `job_postings_fact` depends on `stg_job_postings`, which depends on the source `raw.job_postings_raw`. It also indexes all five tests and their target columns. If salary_year_avg test fails in production, your orchestrator knows immediately that `job_postings_fact` is downstream and may be affected.

## Notes

- **Parse before execute:** Always run `dbt parse` in CI/CD *before* `dbt run`. Catch broken DAGs early, not mid-pipeline.
- **Manifest is immutable per run:** The manifest reflects the state of your code *at parse time*. If you add a model mid-run without re-parsing, it won't exist in the graph and won't execute.
- **Cyclic dependencies are fatal:** If Model A refs Model B and Model B refs Model A (directly or through a chain), parse fails. This catches architectural mistakes before they waste compute.
- **External refs break the DAG:** Using raw SQL `SELECT * FROM schema.table` instead of `{{ ref() }}` or `{{ source() }}` hides dependencies from the manifest. Orchestrators then cannot order tasks correctly.
- **Connects to test selection and exposure tracking:** The manifest powers `dbt test -s model_name`, which finds all tests for that model. It also enables `dbt docs` to show lineage. Understanding the manifest structure is foundational to using these features effectively.
