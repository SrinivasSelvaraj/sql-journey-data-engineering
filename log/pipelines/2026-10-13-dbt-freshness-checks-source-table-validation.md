---
date: 2026-10-13
phase: pipelines
topic: dbt freshness checks: source table validation
---

# dbt freshness checks: source table validation

*Pipelines and orchestration*

## Concept

dbt freshness checks validate that source tables have been updated recently enough to trust downstream models. They query the `updated_at` or similar timestamp column in a source table and fail the dbt run if data is stale beyond a threshold you define. This is critical because stale source data can silently corrupt your entire pipeline—you'll build models on week-old data without realizing it, leading to incorrect analytics and business decisions.

Freshness checks matter most when sources are external (third-party APIs, partner databases, event streams) or updated on irregular schedules. Without them, you might load yesterday's snapshot thinking it's today's, or worse, discover stale data only after stakeholders act on bad numbers. They're also valuable for catching upstream failures: if an ETL job breaks at the source, freshness checks catch it before your models compound the problem.

## Practice

**Problem:** Your `job_postings_fact` table depends on a raw source that updates daily around 2 AM UTC. You need to ensure data is never more than 24 hours old when your dbt models run, and you want the entire pipeline to fail if the source hasn't updated since yesterday.

**Solution:**

```sql
-- In your sources.yml
sources:
  - name: raw_recruiting
    database: raw_db
    schema: recruiting
    tables:
      - name: job_postings_raw
        columns:
          - name: job_id
            tests:
              - unique
              - not_null
        freshness:
          warn_after: {count: 12, period: hour}
          error_after: {count: 24, period: hour}
        loaded_at_field: updated_at

-- In your model (e.g., job_postings_fact.sql)
select
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
from {{ source('raw_recruiting', 'job_postings_raw') }}
where updated_at >= current_date - interval '1 day'
```

Run `dbt source freshness` to validate before your models execute, or add it to your orchestrator as a pre-flight check.

## Notes

- **Loaded-at field must exist**: The column specified in `loaded_at_field` needs to be a timestamp in the source table; if it doesn't exist or isn't maintained, freshness checks always fail or pass incorrectly.
- **Timing assumptions**: Freshness thresholds (`warn_after`, `error_after`) assume predictable update windows; if your source updates irregularly, set conservative windows or build alerting separately.
- **Separate from data quality tests**: Freshness is about *recency*, not correctness—combine it with `dbt test` to catch both stale and wrong data.
- **Orchestration integration**: Wire `dbt source freshness` into your DAG (Airflow, dbt Cloud) so pipeline runs skip or alert when sources are stale; don't just log warnings.
- **Related**: Data lineage and impact analysis (knowing which models depend on a stale source), SLA management, and idempotent model design for safe reruns.
