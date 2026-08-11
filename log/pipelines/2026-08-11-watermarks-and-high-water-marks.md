---
date: 2026-08-11
phase: pipelines
topic: Watermarks and high water marks
---

# Watermarks and high water marks

*Pipelines and orchestration*

## Concept

A **watermark** is a tracked point in a data stream or source system that marks progress through an ordered dataset. The **high water mark** is the maximum value of that tracking column seen so far—typically a timestamp or incrementing ID. Pipelines use watermarks to answer: "What have I already processed? What's new since last run?"

Without watermarks, incremental pipelines either reprocess everything (wasteful) or have no way to detect new data reliably. This breaks idempotency and causes duplicate records, missed updates, and runaway costs. Watermarks make a pipeline resumable: if a job fails mid-run, restart from the last recorded watermark instead of the beginning.

Watermarks work best with **monotonically increasing columns** (timestamps, sequence numbers) in the source data. Store the watermark value in a control table or state file, update it only after successfully committing the batch, and always filter source queries with `WHERE column > last_watermark`.

## Practice

**Problem:** The `job_postings_fact` table grows daily with new job postings. You need an incremental load that fetches only new postings since the last successful run, avoiding duplicates if the pipeline restarts.

```sql
-- Control table to track high water mark
CREATE TABLE IF NOT EXISTS pipeline_state (
  pipeline_name VARCHAR(100) PRIMARY KEY,
  last_watermark DATE,
  updated_at TIMESTAMP
);

-- Initialize watermark if first run
INSERT INTO pipeline_state (pipeline_name, last_watermark, updated_at)
VALUES ('job_postings_incremental', '2024-01-01', CURRENT_TIMESTAMP)
ON CONFLICT DO NOTHING;

-- Extract: fetch only new rows
WITH last_run AS (
  SELECT COALESCE(last_watermark, '2024-01-01'::DATE) AS wm
  FROM pipeline_state
  WHERE pipeline_name = 'job_postings_incremental'
)
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM job_postings_fact
WHERE job_posted_date > (SELECT wm FROM last_run)
ORDER BY job_posted_date;

-- After successful load, update watermark
UPDATE pipeline_state
SET last_watermark = (SELECT MAX(job_posted_date) FROM job_postings_fact WHERE job_posted_date > (SELECT last_watermark FROM pipeline_state WHERE pipeline_name = 'job_postings_incremental')),
    updated_at = CURRENT_TIMESTAMP
WHERE pipeline_name = 'job_postings_incremental';
```

## Notes

- **Watermark column choice matters:** Use stable, non-nullable, monotonically increasing columns. Avoid updated timestamps (past records can change); prefer created_date or sequence IDs.
- **Update watermark *after* commit:** Write data first, then update the control table atomically. If you reverse the order, a crash leaves the watermark ahead of actual data.
- **Timestamp precision risk:** If multiple records share the same second/millisecond, use `>=` on equality but `>` on prior runs to avoid gaps or duplicates.
- **Idempotency + watermarks:** Combine with deduplication keys (job_id) in your target to handle reruns safely—watermark ensures you don't miss data, dedup ensures you don't double-count.
- **Related topics:** check out exactly-once semantics, checkpointing in Spark/Kafka, slowly changing dimensions (SCD), and offset management in streaming platforms.
