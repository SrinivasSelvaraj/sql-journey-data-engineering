---
date: 2026-09-20
phase: pipelines
topic: Exactly-once vs at-least-once delivery semantics
---

# Exactly-once vs at-least-once delivery semantics

*Pipelines and orchestration*

## Concept

**Exactly-once** means each record is processed and written to the destination exactly one time, even if the pipeline restarts. **At-least-once** means records are guaranteed to arrive, but duplicates may occur on failure and retry. In data pipelines, exactly-once is stronger—it prevents double-counting metrics, duplicate rows, and corrupted aggregations. At-least-once is cheaper to implement but requires downstream deduplication.

The difference becomes critical when jobs fail mid-execution. If a task writes 500 rows then crashes, at-least-once will re-run and write those same 500 rows again (plus any new ones). Exactly-once ensures idempotent writes—the destination state is identical whether the job ran once or was retried ten times. Without this guarantee, fact tables accumulate duplicates, revenue metrics spike artificially, and dimension tables break referential integrity.

Most modern data platforms (Spark, Kafka, Flink) support exactly-once through idempotent writes (upsert/merge logic), distributed transactions, or deduplication tokens. The tradeoff is latency and complexity: exactly-once requires checkpointing state, coordinating commits across partitions, and often increases end-to-end latency by 10–50%.

## Practice

**Problem:** A daily batch job loads job postings into `job_postings_fact`. The pipeline crashed after writing 3,000 rows but before updating the watermark table. On retry, it will attempt to re-load the same 3,000 rows. How do you ensure duplicates don't appear in the fact table?

```sql
-- Solution: Use MERGE to implement idempotent upsert
MERGE INTO job_postings_fact AS target
USING staging_job_postings AS source
ON target.job_id = source.job_id 
  AND target.job_posted_date = source.job_posted_date
WHEN MATCHED THEN
  UPDATE SET
    job_title_short = source.job_title_short,
    salary_year_avg = source.salary_year_avg,
    job_work_from_home = source.job_work_from_home,
    job_location = source.job_location
WHEN NOT MATCHED THEN
  INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
  VALUES (source.job_id, source.job_title_short, source.salary_year_avg, 
          source.job_work_from_home, source.job_posted_date, source.job_location);

-- Always update the watermark *after* the MERGE completes atomically
UPDATE pipeline_watermarks 
SET last_processed_date = CURRENT_DATE 
WHERE pipeline_name = 'job_postings_daily';
```

## Notes

- **Atomicity is key:** MERGE and watermark updates must commit together; if the watermark doesn't update, the next run will re-process and deduplicate. Split commits break idempotency.
- **Idempotent vs. transactional:** Exactly-once via MERGE works on immutable keys; without a stable primary key (job_id + posted_date), you'll get logical duplicates.
- **Connects to:** checkpoint/watermark management, distributed transaction coordination, state stores in stream processing, and dead-letter queues for failed records.
- **Common mistake:** Assuming "delete then insert" is idempotent—it's not. If the delete succeeds but insert fails, you've lost data. Use MERGE or INSERT IF NOT EXISTS.
- **Revisit:** Exactly-once in streaming vs. batch is architecturally different; streaming requires offset management (Kafka) while batch relies on state tables (watermarks, checkpoints).
