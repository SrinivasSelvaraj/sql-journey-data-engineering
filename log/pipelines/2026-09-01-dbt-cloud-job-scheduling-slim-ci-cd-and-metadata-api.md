---
date: 2026-09-01
phase: pipelines
topic: dbt Cloud: job scheduling, slim CI/CD and metadata API
---

# dbt Cloud: job scheduling, slim CI/CD and metadata API

*Pipelines and orchestration*

## Concept

dbt Cloud's job scheduling enables automated model runs on fixed cadences or event triggers, replacing manual execution and ensuring data freshness at predictable intervals. Combined with **slim CI/CD**, only modified models and their downstream dependents run during pull requests, dramatically reducing runtime and cloud costs—critical when your DAG has hundreds of models but a single table changed.

The **metadata API** exposes job run logs, model lineage, test results, and execution times programmatically, letting you surface data quality signals to stakeholders without digging into dbt logs. This is where "fail loudly" becomes operational: you can hook job failures into Slack alerts, trigger incident response workflows, or auto-disable downstream consumers when upstream tests fail.

Without scheduling and metadata visibility, pipelines run ad hoc (data staleness), CI takes 2+ hours (feedback loops break), and failures hide in email—causing silent data quality issues that compound downstream. Slim CI/CD is non-negotiable at scale because full-DAG runs become economically unsustainable.

## Practice

**Problem:** Your `job_postings_fact` table is refreshed nightly, but you need to flag jobs posted in the last 24 hours with missing salary data, alert the analytics team if >10% of new postings lack salaries, and only run downstream models (e.g., salary trend analysis) if the test passes.

```sql
-- models/marts/job_postings_quality_check.sql
{{ config(
    materialized='table',
    tags=['daily_check'],
    on_failure='continue'  -- allow downstream to decide
) }}

select
    count(*) as total_new_postings,
    count(case when salary_year_avg is null then 1 end) as missing_salary_count,
    round(
        100.0 * count(case when salary_year_avg is null then 1 end) / count(*),
        2
    ) as pct_missing_salary,
    current_timestamp as check_timestamp
from {{ ref('job_postings_fact') }}
where job_posted_date >= current_date - interval '1 day'
    and job_location is not null
```

**dbt_project.yml job config:**
```yaml
jobs:
  - name: daily_job_postings
    schedule: "0 2 * * *"  # 2 AM daily
    execute_steps:
      - dbt run -m job_postings_fact+
      - dbt test -m job_postings_quality_check
      - dbt run -m +salary_trends --select state:modified+  # slim CI
    triggers:
      - on_failure: send_slack_alert
    metadata_api: enabled  # expose results
```

Hook the metadata API to a Python script that queries `dbt Cloud API → /jobs/{job_id}/runs` and posts to Slack if `pct_missing_salary > 10`.

## Notes

- **Slim CI trap:** `state:modified+` requires dbt to compare current branch against a "base" (usually `main`). If base state is stale or missing, slim CI silently runs everything—audit your deferral setup in CI environments.
- **Job retry logic:** dbt Cloud retries once by default; set explicit retry counts and backoff for unstable data sources (APIs, unoptimized queries) to avoid cascading failures.
- **Metadata API latency:** run metadata queries 30–60 seconds *after* job completion; the API index lags behind actual job state by a few seconds.
- **Adjacent topics:** connect to data observability platforms (Great Expectations, Monte Carlo) via metadata API webhooks; consider event-driven scheduling (Fivetran, Kafka triggers) for low-latency pipelines instead of fixed cron.
- **Revisit:** state comparison artifacts (manifest.json), custom metadata properties (tags, owners), and dbt Cloud multi-tenant limitations when scaling to 50+ jobs.
