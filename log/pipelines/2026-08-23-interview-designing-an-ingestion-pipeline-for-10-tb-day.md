---
date: 2026-08-23
phase: pipelines
topic: Interview: designing an ingestion pipeline for 10 TB/day
---

# Interview: designing an ingestion pipeline for 10 TB/day

*Pipelines and orchestration*

## Concept

A 10 TB/day ingestion pipeline must handle three critical concerns: *volume scaling* (throughput, parallelization, batching), *failure modes* (network drops, schema changes, partial failures), and *observability* (what succeeded, what failed, why). At this scale, a single bad record or missed partition can corrupt downstream analytics within hours. The pipeline must not silently drop data or mask failures—it should crash loudly, allow safe reruns without duplicates, and provide audit trails for reconciliation.

The core tension: speed vs. safety. Naive approaches (streaming everything, no state tracking, fire-and-forget writes) work at 100 GB/day but collapse at 10 TB/day because failure recovery becomes impossible. You need idempotency keys, transaction logs, and checkpointing. Without them, reruns either duplicate data or lose data; you can't tell which.

This is the difference between "data arrives" and "data arrives reliably." At this volume, you're managing SLAs, backpressure, and infrastructure costs. You need to know: *Did today's 10 TB fully land? If not, which 2 TB failed, and is it safe to retry?*

## Practice

**Problem:** Your `job_postings_fact` table receives 10 TB/day of job posting updates from multiple source systems. Jobs can be posted, updated, or removed. Reprocessing the same source file must not create duplicates or lose updates. You need to track what loaded successfully, detect failures mid-load, and safely resume.

```sql
-- 1. Idempotency and audit table (run-once tracking)
CREATE TABLE job_postings_ingestion_log (
  batch_id STRING NOT NULL,
  source_system STRING NOT NULL,
  source_file_path STRING NOT NULL,
  record_count INT,
  bytes_loaded BIGINT,
  load_start_ts TIMESTAMP,
  load_end_ts TIMESTAMP,
  status STRING, -- 'pending', 'success', 'failed', 'partial'
  error_message STRING,
  PRIMARY KEY (batch_id, source_system),
  UNIQUE (source_file_path, batch_id)
);

-- 2. Insert into fact table with deduplication
-- Only load if this batch_id hasn't succeeded before
INSERT INTO job_postings_fact
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  CURRENT_TIMESTAMP as loaded_at
FROM staging_job_postings stg
WHERE NOT EXISTS (
  SELECT 1 FROM job_postings_ingestion_log log
  WHERE log.batch_id = stg.batch_id
    AND log.source_file_path = stg.source_file_path
    AND log.status = 'success'
);

-- 3. After successful load, mark batch complete (idempotent marker)
INSERT INTO job_postings_ingestion_log (
  batch_id, source_system, source_file_path, record_count, 
  bytes_loaded, load_start_ts, load_end_ts, status
)
VALUES (
  '2025-01-15_linkedin_001',
  'linkedin',
  's3://raw/linkedin/2025-01-15/linkedin_001.parquet',
  2500000,
  10737418240, -- 10 GB
  TIMESTAMP('2025-01-15 08:00:00'),
  TIMESTAMP('2025-01-15 08:45:00'),
  'success'
)
ON CONFLICT (batch_id, source_system) DO UPDATE
SET status = 'success', load_end_ts = CURRENT_TIMESTAMP
WHERE status != 'success'; -- only update if not already marked success
```

## Notes

- **Idempotency is non-negotiable:** Use batch IDs or file hashes as unique markers. A rerun of the same file must produce identical results (same row counts, same values). Without this, retry logic becomes dangerous.

- **Fail loudly, not silently:** If 100k records fail schema validation, don't skip them—reject the entire batch, log the error, and alert. Silent partial failures are the worst kind; they corrupt the data lake slowly.

- **Checkpointing and state:** Track *what entered the system* (ingestion log), *what's in progress* (staging), and *what's final* (fact table). This separation lets you restart from any checkpoint without guessing.

- **Adjacent topics:** Consider *schema registry* (to catch breaking changes early), *data contracts* (source systems promise format), and *backpressure handling* (what happens when downstream can't keep up?). Also worth revisiting: partitioning strategy (by date? by source?) and late-arriving facts.

- **10 TB/day math:** At typical row sizes (5 KB), that's ~2 billion records/day or ~23k records/second. Single-threaded anything breaks. You need distributed writes (Spark, bulk loaders)
