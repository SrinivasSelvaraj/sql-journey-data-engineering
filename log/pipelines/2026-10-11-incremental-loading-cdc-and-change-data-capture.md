---
date: 2026-10-11
phase: pipelines
topic: Incremental loading: CDC and change data capture
---

# Incremental loading: CDC and change data capture

*Pipelines and orchestration*

## Concept

Change Data Capture (CDC) is a technique that identifies and extracts only the rows that have changed since the last successful load, rather than reprocessing the entire dataset. This matters because full refreshes become prohibitively expensive as tables grow—a daily full reload of a 500M-row fact table wastes compute, storage, and time. CDC fails silently when you rely on timestamps alone (what if a row is updated without touching `updated_at`?) or when you assume deletes will be caught (they won't—the row is gone). Without it, you either pay exponential cost to scale, or you miss changes entirely and serve stale data to analysts.

In practice, CDC works by reading transaction logs (native CDC like PostgreSQL's WAL or Debezium), maintaining a source-system trigger layer, or comparing snapshots against a watermark table. The pipeline must be idempotent: if a job reruns, it shouldn't duplicate inserts or lose updates. This connects directly to your orchestration layer—it must track which records were processed, handle late-arriving changes, and fail loudly when the CDC mechanism itself breaks (e.g., log retention expires).

## Practice

**Problem:** Your `job_postings_fact` table grows by ~50k rows daily. Currently you reload the entire table every night, which takes 45 minutes and costs $12/run. You need to load only new and changed postings, and detect when a posting's salary or location was corrected.

**Solution:**

```sql
-- 1. Create a CDC tracking table (source of truth for what was processed)
CREATE TABLE job_postings_cdc_watermark (
    last_processed_id BIGINT,
    last_processed_date TIMESTAMP,
    run_id VARCHAR(50),
    row_count INT,
    load_timestamp TIMESTAMP
);

-- 2. Extract changed records since last successful load
WITH last_run AS (
    SELECT COALESCE(MAX(last_processed_id), 0) as prev_max_id,
           COALESCE(MAX(last_processed_date), '1900-01-01'::TIMESTAMP) as prev_date
    FROM job_postings_cdc_watermark
    WHERE run_id IS NOT NULL
)
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, 
       job_posted_date, job_location,
       ROW_NUMBER() OVER (ORDER BY job_id) as batch_seq
FROM job_postings_fact
WHERE job_posted_date > (SELECT prev_date FROM last_run)
   OR (job_posted_date = (SELECT prev_date FROM last_run) 
       AND job_id > (SELECT prev_max_id FROM last_run))
ORDER BY job_posted_date, job_id;

-- 3. After successful load, commit the watermark (atomic with transaction)
INSERT INTO job_postings_cdc_watermark 
    (last_processed_id, last_processed_date, run_id, row_count, load_timestamp)
SELECT MAX(job_id), MAX(job_posted_date), 'run_' || TO_CHAR(NOW(), 'YYYYMMDD_HH24MISS'),
       COUNT(*), NOW()
FROM staged_job_postings_incremental;
```

## Notes

- **Timestamp-only watermarks fail**: If a posting's salary is corrected after `job_posted_date`, your date-based query misses it. Use (date, ID) or (date, hash) compound keys.
- **Deletes are invisible**: If a job posting is retracted, a watermark query won't detect it. You need a separate delete-tracking mechanism (soft deletes, a deletion log table, or full outer join against source).
- **Connects to idempotency**: Your pipeline must handle reruns gracefully. Store the `run_id` and check before inserting duplicates; use MERGE or upsert logic, never plain INSERT.
- **Monitor the watermark itself**: If the watermark table is corrupted or gets ahead of actual processing, the pipeline will silently skip changes. Add data quality checks: compare row counts, backfill on mismatch, alert if watermark jumps unexpectedly.
- **Revisit: late-arriving data** — what if a job posting is inserted with `job_posted_date` from yesterday? You need either a grace period in your query or a replay mechanism for stale changes.
