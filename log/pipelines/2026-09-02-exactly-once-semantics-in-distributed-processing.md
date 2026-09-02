---
date: 2026-09-02
phase: pipelines
topic: Exactly-once semantics in distributed processing
---

# Exactly-once semantics in distributed processing

*Pipelines and orchestration*

## Concept

Exactly-once semantics (EOS) guarantees that each input record is processed and written to the output *exactly one time*, even when failures occur. Without it, you either lose data (at-most-once) or duplicate it (at-least-once). In distributed systems, network partitions, process crashes, and retries make this hard: a job might process a batch, crash before confirming completion, then reprocess the same batch on restart, writing duplicates downstream.

EOS matters most when the cost of duplication is high—financial transactions, user identity deduplication, inventory counts, or metrics that feed billing. It's less critical for exploratory analytics where counts being slightly off is acceptable. The mechanism typically requires idempotent writes (same input always produces same output), transactional checkpointing (atomically mark input consumed + output written), and deduplication windows (reject already-seen records).

Without EOS, you either accept silent data loss (at-most-once) or hidden duplicates that corrupt aggregates and cause cascading errors in downstream dashboards. The damage often goes undetected until analysts notice inconsistencies weeks later.

## Practice

**Problem:** You ingest job postings from an API in micro-batches. A batch of 500 records processes, writes to `job_postings_fact`, but crashes before updating the checkpoint. On restart, the same 500 records are fetched and processed again, creating 500 duplicates. You need exactly-once insertion without losing rows.

```sql
-- Solution: use a staging table + merge with idempotency key (job_id + job_posted_date)
-- Step 1: insert into staging with raw batch
INSERT INTO job_postings_staging (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location, _inserted_at)
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location, CURRENT_TIMESTAMP
FROM incoming_batch;

-- Step 2: merge into fact table using MERGE (atomic operation)
MERGE INTO job_postings_fact AS target
USING job_postings_staging AS source
  ON target.job_id = source.job_id AND target.job_posted_date = source.job_posted_date
WHEN NOT MATCHED THEN
  INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
  VALUES (source.job_id, source.job_title_short, source.salary_year_avg, source.job_work_from_home, source.job_posted_date, source.job_location);

-- Step 3: only after MERGE succeeds, update checkpoint in state store (atomic with output)
UPDATE pipeline_checkpoint SET last_offset = ?, checkpoint_time = CURRENT_TIMESTAMP WHERE pipeline_id = ?;

-- Step 4: truncate staging for next batch
TRUNCATE TABLE job_postings_staging;
```

The idempotency key (`job_id + job_posted_date`) ensures re-running this batch skips already-inserted records. The MERGE is atomic—if the process crashes, either the whole transaction completes or none of it does.

## Notes

- **Idempotency key choice matters:** Use natural or upstream-provided IDs (job_id here), not auto-increments. Duplicates must be detectable by business keys, not row insertion order.
- **Checkpoint placement is critical:** Write checkpoint *after* output succeeds, as part of the same transaction if possible. Checkpointing before output causes data loss; after without transaction causes duplicates.
- **Staging tables are expensive:** For high-volume pipelines, MERGE on staging adds latency. Consider deduplication windows (Kafka/Pulsar) or idempotent sinks (writes with same key overwrite) instead.
- **Connect to: at-least-once + idempotence = exactly-once.** Many streaming frameworks (Spark, Flink) provide EOS guarantees; understand whether your orchestrator (Airflow, dbt, Prefect) passes them through.
- **Revisit:** Test failure scenarios (kill process mid-batch) in staging; verify checkpoint table consistency; measure latency cost of atomic writes.
