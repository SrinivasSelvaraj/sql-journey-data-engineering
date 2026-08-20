---
date: 2026-08-20
phase: python
topic: Delta Lake from Python: reads, writes and time travel
---

# Delta Lake from Python: reads, writes and time travel

*Python for data engineering*

## Concept

Delta Lake is an open-source storage layer that brings ACID transactions, schema enforcement, and time-travel capabilities to data lakes built on object storage. In Python, you interact with Delta tables through PySpark's DataFrame API or through libraries like `delta-rs`, enabling you to read snapshots at any point in history, write with automatic conflict resolution, and recover from data quality failures without manual restoration.

This matters because raw Parquet or CSV pipelines fail silently: concurrent writes corrupt files, schema drift goes undetected, and once bad data lands, recovery requires manual deletion and re-computation. Delta's transaction log (a sequence of JSON files tracking every change) prevents these failures. When your pipeline crashes mid-write, the next run sees a clean table state. When you discover bad records were inserted yesterday, you can revert to the previous version in seconds.

Without Delta, your pipeline becomes fragile at scale. You lose auditability (who changed what when?), you cannot safely do concurrent appends, and debugging a data quality incident means querying multiple intermediate snapshots you never bothered to save.

## Practice

**Problem:** Your `job_postings_fact` table receives daily appends. One morning, a buggy upstream job writes 50,000 rows with `salary_year_avg = NULL` instead of a sensible default. You don't discover this for 12 hours. You need to remove those rows and restore the correct state without re-running the entire pipeline.

```sql
-- View current state and history
SELECT * FROM job_postings_fact VERSION AS OF 0;
DESCRIBE HISTORY job_postings_fact;

-- Identify the version before bad insert (say, version 5)
SELECT COUNT(*) FROM job_postings_fact VERSION AS OF 5;

-- Restore table to version 5
RESTORE TABLE job_postings_fact TO VERSION AS OF 5;

-- Or: soft-delete only bad rows in a new transaction
DELETE FROM job_postings_fact 
WHERE salary_year_avg IS NULL 
  AND job_posted_date = CURRENT_DATE() - INTERVAL 1 DAY;

-- Verify schema and record counts
DESCRIBE job_postings_fact;
SELECT COUNT(*), COUNT(DISTINCT job_id) FROM job_postings_fact;
```

## Notes

- **Schema enforcement by default:** Delta catches `salary_year_avg` arriving as string instead of integer before it hits the table. Set `mergeSchema=False` in writes to fail fast rather than accumulate garbage columns.
- **Time travel is not free:** Vacuum removes old versions after 7 days by default. If you need longer retention, increase `delta.logRetentionDays` or disable vacuum entirely in dev.
- **Partition pruning still applies:** Delta's time-travel reads still benefit from partitioning on `job_posted_date`; querying a single day's version is fast even with 2 years of history.
- **ACID guarantees at table level, not row level:** Multiple jobs can safely append to the same table concurrently, but a DELETE + INSERT race can still produce inconsistent snapshots. Use table locks or single-writer patterns for high-concurrency upserts.
- **Connects to:** data quality frameworks (Great Expectations), monitoring (audit columns + CDC), and lakehouse architecture (Iceberg and Hudi offer similar but distinct trade-offs).
