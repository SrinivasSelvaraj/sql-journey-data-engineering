---
date: 2026-09-19
phase: pipelines
topic: Idempotency keys and deduplication windows
---

# Idempotency keys and deduplication windows

*Pipelines and orchestration*

## Concept

An **idempotency key** is a unique identifier that allows a pipeline step to be safely re-executed without producing duplicate results. When a job fails mid-run and you retry, the key lets your system recognize that "this work was already done" and skip or replace the duplicate. Without idempotency keys, retrying a failed load creates duplicate rows, inflates aggregates, and breaks downstream logic.

Idempotency keys work best with a **deduplication window**—a time range or sequence number that defines which duplicate you keep (usually the latest). For example, if a data source sends the same job posting twice within 5 minutes, you want to keep only one. The window might be "all records from the past hour with matching job_id and source_timestamp" or "all attempts of batch run #42."

This matters most in exactly-once or at-least-once delivery systems. Kafka producers, REST APIs, and cloud object storage don't guarantee a message arrives exactly once; retries are inevitable. Without deduplication, every retry becomes a new row. With it, retries become safe.

## Practice

**Problem:** A job posting ingestion pipeline reads from an API and inserts into `job_postings_fact`. The API sometimes returns the same posting twice in a single batch, and the pipeline itself is retried on failure. You need to load safely without duplicates.

```sql
-- Create idempotency key and deduplication window
WITH source_data AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    CURRENT_TIMESTAMP AS loaded_at,
    -- Idempotency key: combine natural key + batch timestamp
    CONCAT(job_id, '_', DATE(CURRENT_TIMESTAMP)) AS dedup_key,
    ROW_NUMBER() OVER (
      PARTITION BY job_id, DATE(CURRENT_TIMESTAMP) 
      ORDER BY loaded_at DESC
    ) AS dedup_rank
  FROM staging.job_postings_raw
),
deduplicated AS (
  SELECT * 
  FROM source_data
  WHERE dedup_rank = 1  -- Keep latest within dedup window (one day)
)
MERGE INTO job_postings_fact AS target
USING deduplicated AS source
ON target.job_id = source.job_id 
  AND DATE(target.job_posted_date) = DATE(source.job_posted_date)
WHEN MATCHED THEN
  UPDATE SET 
    job_title_short = source.job_title_short,
    salary_year_avg = source.salary_year_avg,
    job_work_from_home = source.job_work_from_home,
    job_location = source.job_location
WHEN NOT MATCHED THEN
  INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, 
          job_posted_date, job_location)
  VALUES (source.job_id, source.job_title_short, source.salary_year_avg, 
          source.job_work_from_home, source.job_posted_date, source.job_location);
```

## Notes

- **Idempotency key design matters:** use natural business keys (job_id + posted_date) plus a batch or time component. Don't use surrogate IDs like UUIDs generated per-run; they defeat the purpose.
- **Deduplication window scope:** keep it as narrow as practical. A 1-day window for daily pipelines is tighter than 30 days; tighter windows reduce stored state and false negatives.
- **MERGE vs. DELETE+INSERT:** MERGE (upsert) is safer and more efficient than deleting duplicates after the fact. Deletion is a separate transaction that can fail, leaving duplicates behind.
- **Connects to:** exactly-once semantics, distributed tracing (log the dedup_key for debugging), transactional outbox pattern, and orchestration layer retries (Airflow, dbt, Dagster all assume pipelines can be idempotent).
- **Common trap:** confusing idempotency keys with deduplication windows. The key identifies the work; the window defines how old a duplicate can be before you treat it as a new record.
