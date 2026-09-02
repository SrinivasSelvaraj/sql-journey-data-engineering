---
date: 2026-09-02
phase: pipelines
topic: Run-to-completion guarantees vs best-effort semantics
---

# Run-to-completion guarantees vs best-effort semantics

*Pipelines and orchestration*

## Concept

**Run-to-completion guarantees** mean a pipeline either finishes successfully or fails and can be safely re-run from the last checkpoint without duplicates or data loss. **Best-effort semantics** mean "do your best" but accept that some records might be lost, duplicated, or partially processed—no promises.

In data pipelines, best-effort is dangerous. If a transformation crashes after inserting 50,000 rows, best-effort leaves you guessing: did those rows process correctly? Should I re-insert them? With run-to-completion, you know exactly where you left off. This matters intensely in fact tables, incremental loads, and any pipeline feeding analytics or decisions. Without it, you accumulate silent data corruption—duplicates creep in, late-arriving facts conflict with old ones, and audits become nightmares.

The cost is modest: idempotency (using MERGE or upsert logic), checkpoint tracking (last processed date, last batch ID), and transaction boundaries. The alternative is chaos.

## Practice

**Problem:** Load job postings daily into `job_postings_fact`. A pipeline runs at 2 AM, crashes after 40 minutes, having processed jobs posted through 2024-01-15. When you re-run it, you must not duplicate those records, yet must capture any new jobs posted since the crash.

**Solution:**

```sql
-- Run-to-completion pattern: merge with checkpoint tracking
CREATE TABLE pipeline_checkpoint (
  table_name VARCHAR,
  last_processed_date DATE,
  updated_at TIMESTAMP,
  PRIMARY KEY (table_name)
);

-- First run: get checkpoint
WITH last_run AS (
  SELECT COALESCE(last_processed_date, '2020-01-01') AS cutoff
  FROM pipeline_checkpoint
  WHERE table_name = 'job_postings_fact'
)
MERGE INTO job_postings_fact AS target
USING (
  SELECT 
    job_id, job_title_short, salary_year_avg, job_work_from_home,
    job_posted_date, job_location
  FROM raw_job_postings
  WHERE job_posted_date > (SELECT cutoff FROM last_run)
    AND job_posted_date <= CURRENT_DATE
) AS source
ON target.job_id = source.job_id
WHEN MATCHED THEN
  UPDATE SET
    job_title_short = source.job_title_short,
    salary_year_avg = source.salary_year_avg,
    job_work_from_home = source.job_work_from_home,
    job_posted_date = source.job_posted_date,
    job_location = source.job_location
WHEN NOT MATCHED THEN
  INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
  VALUES (source.job_id, source.job_title_short, source.salary_year_avg, 
          source.job_work_from_home, source.job_posted_date, source.job_location);

-- Update checkpoint only after merge succeeds
UPDATE pipeline_checkpoint
SET last_processed_date = CURRENT_DATE, updated_at = CURRENT_TIMESTAMP
WHERE table_name = 'job_postings_fact';
```

On re-run after crash, the checkpoint is unchanged, so the query re-processes 2024-01-15 and any new dates. MERGE is idempotent: duplicate job_ids are updated, not re-inserted.

## Notes

- **Checkpoint must be durable:** store it in a separate table with its own transaction; never rely on application memory or logs.
- **Idempotency is non-negotiable:** MERGE, upserts with natural keys, or deduplication before insert. Never append-only for facts.
- **Exactly-once vs at-least-once:** run-to-completion enables exactly-once semantics; best-effort locks you into at-least-once (reconciliation becomes manual and fragile).
- **Partial batch failures:** if your pipeline loads 1000 jobs and fails on record 750, checkpoint must track by job_id or timestamp, not by batch count, so re-run skips the first 749.
- **Connects to:** idempotency keys, watermarking, CDC patterns, transaction log-based replayability (Delta Lake, Iceberg); also audit tables and data lineage for debugging silent failures.
