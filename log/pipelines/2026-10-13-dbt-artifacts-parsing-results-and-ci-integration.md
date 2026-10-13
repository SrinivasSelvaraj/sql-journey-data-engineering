---
date: 2026-10-13
phase: pipelines
topic: dbt artifacts: parsing results and CI integration
---

# dbt artifacts: parsing results and CI integration

*Pipelines and orchestration*

## Concept

dbt artifacts are JSON files generated after `dbt parse` and `dbt run` that document your entire project state: model DAG structure, column-level lineage, test results, timing metadata, and execution logs. The `manifest.json` is the most critical—it's a complete inventory of every resource (model, test, macro, source) with their dependencies, configs, and descriptions. Without parsing artifacts, CI/CD pipelines lack visibility into what changed, whether tests passed, and why builds failed; you lose the ability to implement selective runs (only rebuild downstream models affected by upstream changes) and fail-fast feedback loops that distinguish production-grade pipelines from ad-hoc scripts.

Artifacts enable deterministic, efficient CI by storing the previous state of your project. When a new commit lands, you parse again, diff the manifest against the prior one, and run only models and tests affected by the delta. This pattern—parse → diff → selective run → log results → commit artifacts—turns dbt into a self-documenting, auditable system. Without artifacts persisted in CI (typically in version control or artifact storage), every run is blind; you recompute everything and have no record of *why* a test failed or *which* column cardinality shifted.

## Practice

**Problem:** You need to ensure that whenever `job_postings_fact.salary_year_avg` is modified in a dbt model, all downstream models that reference it are tested for null values before promotion to production. How do you detect this dependency change in CI and trigger only the affected tests?

```sql
-- models/fact/job_postings_fact.sql
{{ config(
    materialized='table',
    tags=['core']
) }}

SELECT
    job_id,
    job_title_short,
    salary_year_avg,  -- lineage tracked in manifest
    job_work_from_home,
    job_posted_date,
    job_location
FROM {{ source('raw_jobs', 'postings') }}
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 180 DAY
```

```yaml
# models/fact/schema.yml – tests tied to manifest lineage
version: 2
models:
  - name: job_postings_fact
    columns:
      - name: salary_year_avg
        tests:
          - not_null:
              config:
                severity: error
          - dbt_expectations.expect_column_values_to_be_in_type_list:
              column_type_list: ['NUMERIC', 'FLOAT64']
      - name: job_id
        tests:
          - unique
          - not_null
```

In CI, after `dbt parse`, diff the manifest to detect that `salary_year_avg` changed. Then use `dbt test --select state:modified` to run only tests on modified columns, and `dbt run --select +job_postings_fact` to run downstream dependents. The artifact (manifest.json) provides the lineage graph needed for state selection.

## Notes

- **Artifact storage:** Persist `manifest.json`, `run_results.json`, and `sources.json` to git or cloud storage (S3, GCS) so CI can always access the prior state for diffing; without this, you cannot do selective runs.
- **`state:modified` selection:** Requires both current and prior manifests; `dbt parse --profiles-dir` generates fresh state; use `dbt parse --no-parse` in downstream jobs to skip re-parsing if artifacts already exist.
- **Test result parsing:** `run_results.json` contains execution time, test status (pass/fail/error), and invocation metadata; parse it post-run to emit metrics (test coverage %, avg model runtime) and fail the CI job if critical tests error.
- **Column-level lineage:** The manifest tracks which columns flow through which models; use `dbt docs generate` + manifest to auto-document impact radius of schema changes and alert on breaking changes before merge.
- **Adjacent topic:** dbt Cloud's native CI feature does this automatically (parse → diff → selective run), but understanding the artifact layer helps debug local CI and integrate dbt into non-dbt-Cloud systems (GitHub Actions, GitLab CI, Airflow).
