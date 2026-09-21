---
date: 2026-09-21
phase: pipelines
topic: At-most-once and data loss acceptance trade-offs
---

# At-most-once and data loss acceptance trade-offs

*Pipelines and orchestration*

## Concept

At-most-once delivery means a message or record is processed zero or one time—never more than once. This is the opposite of exactly-once, which guarantees every message lands exactly one time. At-most-once accepts *data loss* as the price of simplicity: if a job crashes after reading a batch but before writing results, those rows are skipped forever.

This trade-off matters most in non-critical analytics pipelines where missing a few job postings is acceptable, but it becomes dangerous in financial transactions, billing systems, or compliance reporting where every record must be accounted for. Without explicit acceptance of loss, you'll spend months debugging "where did those 47 rows go?" only to realize your pipeline silently drops data during restarts.

At-most-once works because there's no commit-before-read or acknowledgment step. Read → process → write. If write fails, restart from the beginning of the same batch—but if you crash mid-process, the rows you already read are gone. This is fast and simple, but requires honest documentation and alerting on what percentage of data you're willing to lose.

## Practice

**Problem:** A daily job ingests job postings from an API into `job_postings_fact`. The pipeline reads from a cursor (offset-based), transforms data, and inserts. If the process crashes after reading 500 rows but before the insert commits, those 500 rows are lost on restart because the cursor already moved forward. You need to detect and accept this loss explicitly.

```sql
-- At-most-once: read without locking, accept loss on failure
BEGIN TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- Read the next batch (no rewind guarantee)
WITH batch AS (
  SELECT job_id, job_title_short, salary_year_avg, 
         job_work_from_home, job_posted_date, job_location
  FROM staging_job_postings
  WHERE processed_flag = FALSE
  LIMIT 500
)
INSERT INTO job_postings_fact
SELECT * FROM batch;

-- Move cursor forward (no rollback on insert failure)
UPDATE staging_job_postings
SET processed_flag = TRUE
WHERE job_id IN (SELECT job_id FROM batch);

COMMIT;

-- Log the loss explicitly
INSERT INTO pipeline_loss_log(pipeline_name, batch_size, timestamp, notes)
VALUES('job_postings_ingest', 500, NOW(), 
       'At-most-once: 500 rows may be lost if crash occurs between batch read and commit');
```

## Notes

- **Common mistake:** Treating at-most-once as "good enough" without measuring actual loss rates. Set up alerts that fire when a pipeline doesn't complete; silence is data loss.
- **Exactly-once alternative:** Use idempotent keys (job_id) with `ON CONFLICT DO UPDATE` or dual-write patterns, but this costs more complexity and latency—reserve it for critical pipelines.
- **Failure modes:** At-most-once hides partial failures well (some rows inserted, some lost) but makes post-mortem analysis hard. Always log batch boundaries and checkpoints.
- **Adjacent topics:** Checkpoint management, transaction isolation levels, idempotency keys, and dead-letter queues for failed records.
- **Revisit when:** Stakeholders ask "why are row counts off by 47?" or compliance requires audit trails—that's when you need to move upstream to exactly-once.
