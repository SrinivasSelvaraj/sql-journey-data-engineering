---
date: 2026-08-12
phase: pipelines
topic: dbt: incremental models and merge strategies
---

# dbt: incremental models and merge strategies

*Pipelines and orchestration*

## Concept

Incremental models process only new or changed data rather than rebuilding tables from scratch every run. Without them, a pipeline that ingests millions of daily rows must reprocess everything each time, wasting compute and time. dbt's `incremental` materialization lets you append or upsert only fresh records, making pipelines both faster and cheaper.

The key decision is *merge strategy*: how to handle updates to existing records. **Append-only** (simplest) adds new rows blindly—good for immutable events but breaks if a source corrects a record. **Delete+insert** removes old partitions and rewrites them—safe but slower. **Merge/upsert** updates matching rows in place—most efficient but requires a unique key and careful conflict logic.

Without explicit merge strategies, you either duplicate data (silently breaking aggregations), lose updates (stale reporting), or reprocess everything (defeating the purpose). The strategy you pick determines whether your pipeline is reliable or a silent data quality trap.

## Practice

**Problem:** `job_postings_fact` receives new postings daily, but job titles and salary data sometimes get corrected in the source up to 7 days after posting. You need incremental loads that capture corrections without duplication, keyed on `job_id` and `job_posted_date`.

```sql
{{
  config(
    materialized='incremental',
    unique_key=['job_id', 'job_posted_date'],
    merge_strategy='merge',
    incremental_strategy='merge'
  )
}}

select
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  current_timestamp() as dbt_loaded_at
from {{ source('job_boards', 'postings_raw') }}

{% if execute and execute_macros == true and flags.FULL_REFRESH is False %}
  where job_posted_date >= (select max(job_posted_date) - interval 7 day from {{ this }})
{% endif %}
```

The composite `unique_key` prevents duplicates. The 7-day lookback window catches late corrections. On full refresh, it rebuilds; on incremental runs, it merges only recent data into existing rows.

## Notes

- **Unique key mistakes:** Forgetting to define a key or using a non-unique one silently duplicates rows. Always validate cardinality in source data before committing to a key.
- **Lookback windows:** Make them wide enough to catch source corrections (often 7–14 days), otherwise you'll miss updates and ship stale data to downstream tables.
- **Merge strategy trade-offs:** PostgreSQL/Snowflake/BigQuery each handle `merge` differently—test idempotency (running twice = running once) before production.
- **Adjacent topics:** Connects to SCD Type 2 (slowly changing dimensions) for historical tracking, partition pruning for performance, and the `dbt_valid_from`/`dbt_valid_to` pattern for audit trails.
- **Revisit:** Test incremental logic with `dbt run-operation macro_name --select job_postings_fact --full-refresh` to verify the non-incremental path still works.
