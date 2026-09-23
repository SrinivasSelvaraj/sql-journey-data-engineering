---
date: 2026-09-23
phase: pipelines
topic: CDC: change data capture and log mining
---

# CDC: change data capture and log mining

*Pipelines and orchestration*

## Concept

Change Data Capture (CDC) enables pipelines to detect and process only rows that have been inserted, updated, or deleted since the last run—rather than scanning entire tables. This is critical for cost efficiency and latency: reprocessing millions of rows daily when only hundreds changed wastes compute and delays analytics. Log mining (query logs, database transaction logs, or WAL files) is the most reliable CDC pattern; it reads the source's immutable audit trail instead of polling columns or comparing snapshots, avoiding race conditions and missed deletes.

CDC failures are loud: if your pipeline misses a change, downstream analytics diverges from source-of-truth silently. Without CDC, you either over-extract (full table scans) and hide real problems under resource bloat, or under-extract (incomplete polls) and ship wrong numbers to stakeholders. Proper CDC pipelines track LSN (Log Sequence Number) or transaction timestamps, persist them in state tables, and resume from the last safe checkpoint—enabling both safety and speed.

## Practice

**Problem:** Job postings are frequently updated (salary corrections, location changes, delisted). Your daily pipeline currently scans the entire 50M-row table and re-aggregates salary statistics. Recalculation is expensive; you need to detect only changed rows since yesterday's run.

```sql
-- State table: persist CDC checkpoint
CREATE TABLE cdc_checkpoint (
  source_table VARCHAR,
  last_lsn BIGINT,
  last_run TIMESTAMP,
  PRIMARY KEY (source_table)
);

-- On first run or recovery, capture current LSN
INSERT INTO cdc_checkpoint (source_table, last_lsn, last_run)
VALUES ('job_postings_fact', 0, CURRENT_TIMESTAMP);

-- CDC query: get only changed rows since last checkpoint
WITH last_state AS (
  SELECT last_lsn FROM cdc_checkpoint WHERE source_table = 'job_postings_fact'
)
SELECT 
  job_id, 
  job_title_short, 
  salary_year_avg, 
  job_work_from_home,
  job_posted_date,
  job_location,
  __change_type,  -- 'INSERT', 'UPDATE', 'DELETE'
  __lsn            -- log sequence number
FROM job_postings_fact
WHERE __lsn > (SELECT last_lsn FROM last_state)
ORDER BY __lsn;

-- After successful processing, update checkpoint
UPDATE cdc_checkpoint 
SET last_lsn = (SELECT MAX(__lsn) FROM processed_changes),
    last_run = CURRENT_TIMESTAMP
WHERE source_table = 'job_postings_fact';
```

## Notes

- **Checkpoint atomicity:** Update the state table only *after* successful downstream write; if processing fails mid-pipeline, the next run retries from the same LSN and idempotency handles re-ingested rows.
- **Delete handling:** CDC is the only reliable way to detect deletes; snapshot-diff methods will miss them entirely. Always check `__change_type = 'DELETE'` and handle soft deletes vs. hard deletes explicitly.
- **Connective topics:** CDC unlocks real-time replication (Debezium, Kafka Connect), incremental fact tables, and SCD Type 2 slowly-changing-dimension logic—all require treating changes as events, not static rows.
- **Common mistakes:** Relying on `UPDATED_AT` columns as CDC (clock skew, missed updates), forgetting to handle PK changes, and restarting the checkpoint to 0 after one failure (causes full rescans).
- **Testing:** Mock LSN advances and deletion scenarios; a broken CDC checkpoint can silently corrupt your warehouse for weeks before detection.
