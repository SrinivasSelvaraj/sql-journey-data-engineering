---
date: 2026-10-28
phase: pipelines
topic: Deduplication logic in idempotent pipelines
---

# Deduplication logic in idempotent pipelines

*Pipelines and orchestration*

## Concept

Deduplication logic ensures that re-running a pipeline produces identical results without multiplying data. In idempotent pipelines, the same input always yields the same output state—no duplicates accumulate across retries. Without deduplication, a failed job that reruns will insert the same rows twice, corrupting aggregations, counts, and downstream reports.

Deduplication matters most when your pipeline loads data from APIs or log systems where the same records may be fetched multiple times, or when orchestration tools (Airflow, dbt) retry failed tasks. The most common approach is **upsert logic**: identify a unique key (primary key or business key), then INSERT new rows or UPDATE existing ones if the key already exists.

Deduplication breaks silently when you treat each pipeline run as append-only without checking for duplicates. A daily job that crashes and reruns the same day will double-count events. A weekly backfill that overlaps partially with the previous week will create ghost records. This is why idempotent pipelines require explicit duplicate detection tied to your business key, not just timestamps.

## Practice

**Problem:** Your `job_postings_fact` table loads job data from an external API daily. If the pipeline fails mid-run and reruns, jobs already inserted will be inserted again. You need the pipeline to safely rerun without duplicating rows, and you want to capture updates if a job's salary or location changes.

```sql
-- Idempotent upsert: merge new data with existing data using job_id as the business key
MERGE INTO job_postings_fact AS target
USING (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    CURRENT_TIMESTAMP AS updated_at
  FROM staging_job_postings
) AS source
ON target.job_id = source.job_id
WHEN MATCHED THEN
  UPDATE SET
    job_title_short = source.job_title_short,
    salary_year_avg = source.salary_year_avg,
    job_work_from_home = source.job_work_from_home,
    job_location = source.job_location,
    updated_at = source.updated_at
WHEN NOT MATCHED THEN
  INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location, updated_at)
  VALUES (source.job_id, source.job_title_short, source.salary_year_avg, source.job_work_from_home, source.job_posted_date, source.job_location, source.updated_at);
```

## Notes

- **Composite keys matter**: if `job_id` alone isn't unique across time or context, use `(job_id, job_posted_date)` or add a source system identifier to avoid false merges.
- **Stage-then-merge pattern**: load raw data into a staging table first, then merge into the fact table. This isolates failures and lets you rerun the merge without re-fetching.
- **Delete detection**: MERGE handles inserts and updates, but not deletes. If a job posting is removed from the source, you'll need a separate soft-delete or archival step.
- **Timestamp columns**: track `inserted_at` (immutable) and `updated_at` (changes on upsert) to debug lineage and audit when data last changed.
- **Related concepts**: idempotency connects to state management, slowly changing dimensions (Type 1 vs Type 2), and airflow task idempotency keys; revisit after mastering incremental loads and partitioning strategies.
