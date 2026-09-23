---
date: 2026-09-23
phase: pipelines
topic: Incremental processing and state management
---

# Incremental processing and state management

*Pipelines and orchestration*

## Concept

Incremental processing means computing only the *delta*—new or changed data—rather than reprocessing the entire dataset on every run. Without it, a pipeline that ingests 100M rows daily will recompute all 100M rows plus the 1M new ones, wasting compute and delaying results. State management is the mechanism that tracks what has been processed: a high-water mark (max date/ID seen), a checksum table, or a change data capture log. Together they prevent duplicate work and duplicate data in your warehouse.

This matters acutely in production because full refreshes become prohibitively expensive at scale, and the longer a pipeline runs, the wider the window for failure. Incremental + state lets you restart safely: if a job fails at 3am, you re-run from the last committed checkpoint, not from day one. Without state, you lose idempotency—reruns corrupt your facts with duplicates or miss updates entirely.

## Practice

**Problem:** Your `job_postings_fact` table receives 50k new job postings daily. A full refresh takes 8 minutes; you have 24-hour latency tolerance but want to run hourly. Design an incremental load that captures only new postings and recovers safely if the pipeline crashes mid-run.

```sql
-- State table: tracks the last processed timestamp
CREATE TABLE IF NOT EXISTS pipeline_state (
  table_name VARCHAR,
  last_processed_date TIMESTAMP,
  checkpoint_id INT,
  updated_at TIMESTAMP,
  PRIMARY KEY (table_name)
);

-- Initialize or update the high-water mark
INSERT INTO pipeline_state (table_name, last_processed_date, checkpoint_id, updated_at)
VALUES ('job_postings_fact', CAST('1900-01-01' AS TIMESTAMP), 0, NOW())
ON CONFLICT (table_name) DO NOTHING;

-- Incremental load: fetch only rows posted since last checkpoint
WITH state AS (
  SELECT last_processed_date FROM pipeline_state 
  WHERE table_name = 'job_postings_fact'
)
INSERT INTO job_postings_fact (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT 
  job_id, 
  job_title_short, 
  salary_year_avg, 
  job_work_from_home, 
  job_posted_date, 
  job_location
FROM staging.job_postings_raw
WHERE job_posted_date > (SELECT last_processed_date FROM state)
  AND job_posted_date <= CURRENT_DATE;

-- Atomic state update: only commit if insert succeeded
UPDATE pipeline_state 
SET last_processed_date = CURRENT_DATE, checkpoint_id = checkpoint_id + 1, updated_at = NOW()
WHERE table_name = 'job_postings_fact';
```

## Notes

- **Mistake: trusting `MAX(timestamp)` alone.** If two rows have the same `job_posted_date`, a restart from that date loads them twice. Use `(timestamp, ID)` tuples or add a sequence number to state.
- **Mistake: updating state before the load commits.** If your INSERT fails after state update, the next run skips data. Always update state *after* successful insert, in the same transaction where possible.
- **Connects to:** idempotency (rerunning must not corrupt data), monitoring (alert when state.updated_at lags), and partition pruning (use `job_posted_date` in your WHERE clause to skip scanning old partitions).
- **Gotcha with late-arriving data:** postings backdated or corrected after ingestion won't be caught by a forward-moving high-water mark. Consider a secondary "CDC window" that rechecks the last N days weekly.
- **State versioning:** log checkpoint_id and timestamps so you can debug "why did we reprocess Nov 15?" and audit the lineage of corrections.
