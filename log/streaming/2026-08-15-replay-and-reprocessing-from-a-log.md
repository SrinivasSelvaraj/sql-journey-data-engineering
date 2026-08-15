---
date: 2026-08-15
phase: streaming
topic: Replay and reprocessing from a log
---

# Replay and reprocessing from a log

*Streaming and distributed processing*

## Concept

Replay and reprocessing is the ability to re-run stream processing logic against historical events, starting from any point in time. This is critical because streaming systems often encounter bugs, schema changes, or business logic updates *after* data has already been processed. Without replay capability, you either lose historical correctness or maintain two separate batch systems. The key enabler is an **immutable event log** (Kafka, Pulsar, or cloud event stores) that preserves every event with its original timestamp, allowing you to rewind and recompute.

Replay matters most when: (1) you discover a calculation error weeks later, (2) you add new features that require historical context (e.g., "calculate tenure for all users retroactively"), or (3) you deploy a breaking schema migration. Without it, you're stuck patching production state manually or accepting data gaps. The cost of replay is storage (keeping the log) and compute (re-running the pipeline), but it's far cheaper than data loss or operational firefighting.

## Practice

**Problem:** Your streaming pipeline calculates rolling 30-day average salary by job title from incoming job postings. You discover the logic was wrong for remote jobs—they should be weighted 1.2× because they typically pay less but offer flexibility. You need to recalculate the metric for all job postings from the past three months without losing current state.

```sql
-- Step 1: Replay from the event log, applying corrected logic
WITH replayed_events AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg * CASE WHEN job_work_from_home THEN 1.2 ELSE 1.0 END AS adjusted_salary,
    job_posted_date
  FROM job_postings_log  -- immutable event store, partitioned by job_posted_date
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
),
corrected_metrics AS (
  SELECT 
    job_title_short,
    job_posted_date,
    AVG(adjusted_salary) OVER (
      PARTITION BY job_title_short 
      ORDER BY job_posted_date 
      ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) AS rolling_30d_avg_salary
  FROM replayed_events
)
-- Step 2: Upsert corrected state back into the materialized view
MERGE INTO job_title_salary_metrics AS target
USING corrected_metrics AS source
ON target.job_title_short = source.job_title_short 
   AND target.metric_date = source.job_posted_date
WHEN MATCHED THEN UPDATE SET 
  rolling_30d_avg_salary = source.rolling_30d_avg_salary,
  last_recalculated = NOW()
WHEN NOT MATCHED THEN INSERT 
  (job_title_short, metric_date, rolling_30d_avg_salary, last_recalculated)
  VALUES (source.job_title_short, source.job_posted_date, source.rolling_30d_avg_salary, NOW());
```

## Notes

- **Immutable log is non-negotiable:** If you compact, delete, or mutate events, replay becomes impossible. Kafka retention and partitioning strategy directly determines replay window and speed.
- **Timestamp semantics matter:** Use event time (when the job was posted), not processing time (when you received it). Skewed clocks or late data break replay reproducibility.
- **Idempotency is essential:** Replay must produce identical results on second run. Use deterministic UDFs, avoid NOW() or RAND() in transformation logic, and make state writes idempotent (upserts, not appends).
- **State versioning:** Track which version of the pipeline produced each output. When replaying, either fork state versions or rebuild from scratch—mixing versions causes corruption.
- **Adjacent topics:** Exactly-once semantics, event sourcing patterns, time-travel queries (Iceberg, Delta Lake snapshots), and dead-letter queues for handling malformed events during replay.
