---
date: 2026-08-12
phase: pipelines
topic: dbt: sources, freshness and snapshots
---

# dbt: sources, freshness and snapshots

*Pipelines and orchestration*

## Concept

**Sources** are dbt's way of declaring external data dependencies—they document where your raw data lives and make lineage explicit. Instead of writing `FROM raw_schema.table`, you define a source in YAML, reference it with `source()`, and gain the ability to test upstream data quality and track dependencies. **Freshness checks** automatically verify that source tables are being updated as expected; if a table hasn't been refreshed since a threshold you define, dbt can fail the run loudly, catching stale data before it corrupts downstream models. **Snapshots** capture point-in-time changes to slowly-changing dimensions—they track when rows were inserted, updated, or deleted by storing multiple versions with validity dates, enabling historical analysis without losing the original data.

Together, these three mechanisms transform raw data ingestion from a silent black box into an observable, validated pipeline stage. Without sources, you lose lineage and can't validate freshness. Without freshness checks, you silently process day-old data and wonder why metrics are flat. Without snapshots, slowly-changing dimensions like job titles or salary bands get overwritten, and you can never reconstruct what changed and when.

## Practice

**Problem:** Your `job_postings_fact` table is loaded daily from an upstream system, but the loading process sometimes fails silently and the table doesn't update. You need to catch stale data, track when job locations change, and document that this data comes from a specific source system.

```sql
-- dbt/models/staging/sources.yml
version: 2
sources:
  - name: raw_jobs_db
    description: "Raw job postings from the HR system"
    tables:
      - name: job_postings
        description: "Daily feed of active job postings"
        freshness:
          warn_after: {count: 24, period: hour}
          error_after: {count: 36, period: hour}
        loaded_at_field: job_posted_date
        columns:
          - name: job_id
            tests:
              - unique
              - not_null
          - name: salary_year_avg
            tests:
              - dbt_utils.accepted_range:
                  min_value: 20000
                  max_value: 500000

-- dbt/models/staging/stg_job_postings.sql
select
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
from {{ source('raw_jobs_db', 'job_postings') }}

-- dbt/snapshots/job_postings_snapshot.sql
{% snapshot job_postings_location_snapshot %}
  {{
    config(
      target_schema='snapshots',
      unique_key='job_id',
      strategy='timestamp',
      updated_at='job_posted_date',
    )
  }}
  select
    job_id,
    job_title_short,
    job_location,
    job_posted_date
  from {{ source('raw_jobs_db', 'job_postings') }}
{% endsnapshot %}

-- Run freshness checks:
-- dbt source freshness

-- Query the snapshot to see location changes:
-- select job_id, job_location, dbt_valid_from, dbt_valid_to 
-- from snapshots.job_postings_location_snapshot 
-- where job_id = 123 order by dbt_valid_from
```

## Notes

- **Common mistake:** Setting freshness thresholds too tight (e.g., 1 hour) then getting paged at 2 AM when a scheduled load runs 75 minutes late; be realistic about your infrastructure's actual SLAs.
- **Snapshot strategy choice matters:** `timestamp` strategy (faster, requires an `updated_at` column) vs. `check` strategy (slower, can detect changes on any column); timestamp is preferred if your source provides it.
- **Freshness checks only validate; they don't fix:** If `dbt source freshness` errors, you still need separate alerting and retry logic in your orchestrator (Airflow, dbt Cloud) to actually halt downstream runs.
- **Snapshots accumulate:** They're append-only tables that grow indefinitely; plan for storage and query performance, and consider archiving old snapshot data periodically.
- **Connects to:** data quality testing (dbt tests on sources catch upstream issues), lineage visualization (sources make `dbt docs` more useful), and SCD Type 2 pattern recognition (snapshots are how you implement SCD Type 2 in dbt).
