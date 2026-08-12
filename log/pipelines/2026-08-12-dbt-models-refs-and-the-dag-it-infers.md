---
date: 2026-08-12
phase: pipelines
topic: dbt: models, refs and the DAG it infers
---

# dbt: models, refs and the DAG it infers

*Pipelines and orchestration*

## Concept

A dbt **model** is a SQL file that transforms raw data into a semantic object—a table or view—with a clear business meaning. Each model declares its dependencies using the `ref()` function, which references other models by name rather than hardcoding table names. This creates a directed acyclic graph (DAG) that dbt infers at parse time.

The DAG matters because it tells dbt *what order to run models in*, *which models are affected by upstream changes*, and *which tests to re-run when something breaks*. Without explicit refs, you hardcode table names and lose all dependency tracking—a change upstream (schema rename, data removal) silently breaks downstream models with no signal. You also can't parallelize execution or do incremental refreshes intelligently.

Breaking without it: if a staging model changes its output column name and three downstream models query it by hardcoded table reference, all three fail silently until runtime. With refs, dbt knows the lineage and can warn you or run tests first. It also enables `dbt run --select model_a+` to run a model and everything that depends on it, or `dbt run --select +model_a` to run everything feeding into it.

## Practice

**Problem:** You have raw job postings data and need to build a fact table where salaries under $30k are flagged as potentially unreliable, job titles are standardized to short form, and the table is sorted by post date. You have a staging model `stg_job_postings` that cleans basic columns. Build the fact model using refs and document the DAG.

```sql
-- models/facts/job_postings_fact.sql

{{ config(
    materialized='table',
    indexes=[{'columns': ['job_posted_date']}]
) }}

SELECT
    job_id,
    job_title_short,
    CASE 
        WHEN salary_year_avg < 30000 THEN salary_year_avg
        ELSE salary_year_avg 
    END AS salary_year_avg,
    salary_year_avg < 30000 AS salary_potentially_unreliable,
    job_work_from_home,
    job_posted_date,
    job_location,
    CURRENT_TIMESTAMP AS dbt_loaded_at
FROM {{ ref('stg_job_postings') }}
WHERE job_posted_date IS NOT NULL
ORDER BY job_posted_date DESC
```

The `{{ ref('stg_job_postings') }}` macro replaces the table name at runtime and registers the dependency in the DAG. dbt will always run `stg_job_postings` first, then `job_postings_fact`.

## Notes

- **Circular refs are an error**: if model A refs B and B refs A, dbt fails at parse time. Design your models in layers (staging → intermediate → fact/dimension) to keep the DAG acyclic.
- **Refs only work within dbt projects**: to depend on external tables (raw data, third-party schemas), use `source()` instead; it documents lineage but does not assume you own the table.
- **DAG visualization is your debugging tool**: run `dbt docs generate && dbt docs serve` to see the full dependency graph in the UI. Use it before running anything in production to catch surprises.
- **Incremental models need refs too**: when you use `dbt run --select state:modified+`, dbt uses the DAG to find which downstream models to rebuild; refs are what makes this possible.
- **Test early, test often on the DAG**: place generic tests (uniqueness, not-null) on model outputs; combined with refs, dbt can re-run only affected tests after an upstream change.
