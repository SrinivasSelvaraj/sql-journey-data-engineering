---
date: 2026-09-20
phase: pipelines
topic: Checkpointing intervals and recovery time objectives
---

# Checkpointing intervals and recovery time objectives

*Pipelines and orchestration*

## Concept

Checkpointing intervals determine how frequently a pipeline saves its state—which rows processed, which transformations completed, which files landed. Without checkpoints, a failure mid-run forces you to restart from the beginning, reprocessing data you've already touched and risking duplicate inserts or incomplete transformations. Recovery Time Objective (RTO) is how quickly you need to resume after failure; checkpointing directly controls this. A pipeline that checkpoints every 1,000 rows recovers in seconds; one that checkpoints once per day may need an hour to restart and verify state.

Checkpointing matters most in long-running batch jobs (multi-hour ETL runs) and in stateful streaming. It's cheap insurance: writing a checkpoint table or marker file costs little compared to reprocessing millions of rows. Without it, you either accept data loss, duplicate data, or manual recovery steps—all poison in production. The checkpoint must capture enough detail to resume *idempotently*: knowing both what succeeded and what didn't, so reruns don't create duplicates or gaps.

## Practice

**Problem:** A nightly job loads new job postings into `job_postings_fact` from a staging table. The source file contains 500k rows. If the job fails halfway through the insert, the next run will duplicate the first 250k rows already committed. Design a checkpoint strategy to make the rerun safe.

```sql
-- Create checkpoint table to track batch progress
CREATE TABLE job_postings_checkpoint (
  batch_id STRING,
  checkpoint_timestamp TIMESTAMP,
  rows_processed INT,
  last_processed_job_id INT,
  status STRING  -- 'in_progress', 'completed', 'failed'
);

-- Insert with checkpoint every 50k rows
BEGIN TRANSACTION;
  INSERT INTO job_postings_fact
  SELECT jp.* 
  FROM job_postings_staging jp
  WHERE jp.job_id > (
    SELECT COALESCE(MAX(last_processed_job_id), 0)
    FROM job_postings_checkpoint
    WHERE batch_id = 'batch_20250117' AND status = 'completed'
  )
  AND jp.job_id <= (SELECT MAX(job_id) FROM job_postings_staging)
  LIMIT 50000;
  
  UPDATE job_postings_checkpoint
  SET rows_processed = rows_processed + 50000,
      last_processed_job_id = (SELECT MAX(job_id) FROM job_postings_fact WHERE job_posted_date = CURRENT_DATE),
      checkpoint_timestamp = CURRENT_TIMESTAMP,
      status = 'in_progress'
  WHERE batch_id = 'batch_20250117';
COMMIT;

-- After all chunks succeed, mark complete
UPDATE job_postings_checkpoint
SET status = 'completed'
WHERE batch_id = 'batch_20250117';
```

## Notes

- **Checkpoint vs. transaction:** A database transaction guarantees atomicity for one operation; a checkpoint records progress *across* operations so you know where to resume. You often need both.
- **The idempotency rule:** Always filter by `last_processed_id` or `max_timestamp` on rerun. Never rely on row counts alone—they're meaningless after a partial failure.
- **Connected to:** data lineage (what triggered this batch?), data quality gates (fail before checkpoint so bad data doesn't move forward), and exactly-once semantics in streaming.
- **Common mistake:** Checkpointing the source (how many rows read) instead of the sink (how many rows successfully landed). The source tells you nothing about what downstream succeeded.
- **Revisit:** How to handle out-of-order arrivals (late events) and how checkpoint strategy changes for append-only vs. slowly-changing dimension loads.
