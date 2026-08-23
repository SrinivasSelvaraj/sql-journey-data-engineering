---
date: 2026-08-23
phase: pipelines
topic: Testing incremental logic: the dbt state trick
---

# Testing incremental logic: the dbt state trick

*Pipelines and orchestration*

## Concept

Incremental models in dbt process only new or changed data to save compute and time, but they're dangerous without proper testing. The "dbt state trick" uses `dbt state:modified` to selectively test only the models and tests affected by recent code changes, preventing you from shipping logic bugs that only surface on full refreshes. This matters because incremental logic is stateful—it depends on what was already loaded—and a model that works fine on day one can silently corrupt data months later if your `unique_key` or filter logic drifts.

Without explicit state testing, you might pass local tests (which often run on filtered dev data) but fail in production where the full historical dataset exposes edge cases: duplicate key handling, timestamp boundary conditions, or late-arriving facts. The trick catches these by running dbt's internal state graph to identify exactly which tests are relevant, rather than re-running your entire test suite or guessing which models to validate.

## Practice

**Problem:** Your `job_postings_fact` table is incremental, keyed on `job_id` and partitioned by `job_posted_date`. You add a new column `job_location_cleaned` (normalized location), but your incremental filter only looks at `MAX(job_posted_date)`. Without state-based testing, you won't catch that old records never get the cleaned location value.

```sql
-- dbt model: job_postings_fact
{{
  config(
    materialized='incremental',
    unique_key='job_id',
    on_schema_change='fail'
  )
}}

SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  CASE 
    WHEN job_location ILIKE '%remote%' THEN 'Remote'
    ELSE INITCAP(job_location)
  END AS job_location_cleaned
FROM {{ source('raw_jobs', 'postings') }}

{% if execute and execute_macros and flags.FULL_REFRESH == false %}
  WHERE job_posted_date >= (
    SELECT COALESCE(MAX(job_posted_date), '1900-01-01')
    FROM {{ this }}
  )
{% endif %}
```

**Solution:** Run `dbt test --select state:modified --state ./target --defer` after code changes. This compares your current branch against the production state, tests only affected models, and catches the location_cleaned logic gap before deployment.

## Notes

- **Common trap:** Incremental models silently succeed locally because dev data is small; always test against a production-scale sample or use `dbt snapshot` to version historical state.
- **Unique key brittleness:** If your `unique_key` doesn't match your business logic (e.g., keying on `job_id` alone when the same job is posted twice), incremental upserts corrupt data; state testing can't fix bad keys, but deterministic tests on `unique_key` columns catch this early.
- **Adjacent topics:** Connects to dbt's `freshness` checks (data staleness), `meta` tags for custom test logic, and orchestration tool hooks (Airflow's `get_dagrun_state()`, dbt Cloud's partial parsing).
- **Worth revisiting:** The distinction between `dbt test --select state:modified` (compare current code to last commit) vs. `state:new` (new models only)—easy to confuse in CI/CD pipelines.
- **Refresh strategy:** Even with state testing, run a full refresh monthly or after major schema changes; incremental logic decays silently if assumptions shift.
