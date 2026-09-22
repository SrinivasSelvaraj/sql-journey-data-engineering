---
date: 2026-09-22
phase: pipelines
topic: Replayability and historical data backfill
---

# Replayability and historical data backfill

*Pipelines and orchestration*

## Concept

Replayability means a pipeline can safely re-execute historical data transformations and produce identical results without duplication or corruption. This is critical when you discover bugs in transformation logic, need to backfill missing data, or rebuild tables after schema changes. Without replayability, you either accept stale/incorrect data or manually delete and restart—both operationally dangerous.

Historical data backfill is the process of applying current (corrected) logic to past data. It requires idempotent operations: inserting or upserting the same record twice yields the same final state. This is where many pipelines fail—they append duplicates, lose intermediate state, or create referential integrity violations because they weren't designed with replay in mind.

The foundation is **immutable input snapshots** and **deterministic, stateless transformations**. If your source data changes between runs (timestamps shift, records vanish), replay becomes impossible. If your transformation depends on "current time" or external state, the same input produces different outputs. Both patterns break backfill.

## Practice

**Problem:** You discover that job postings from 2023 were loaded with `job_work_from_home` set incorrectly (all NULL instead of parsed from `job_location`). You need to backfill the entire table without duplicating 2024 records or losing recent inserts.

```sql
-- 1. Create immutable staging table from source (snapshot logic)
CREATE TABLE job_postings_staging AS
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  CASE WHEN job_location ILIKE '%remote%' THEN TRUE ELSE FALSE END AS job_work_from_home,
  job_posted_date,
  job_location,
  CURRENT_TIMESTAMP AS loaded_at
FROM raw_job_postings
WHERE job_posted_date >= '2023-01-01';

-- 2. Truncate and replay (idempotent via PRIMARY KEY)
TRUNCATE TABLE job_postings_fact;

INSERT INTO job_postings_fact 
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM job_postings_staging
ON CONFLICT (job_id) DO UPDATE SET
  job_work_from_home = EXCLUDED.job_work_from_home,
  salary_year_avg = EXCLUDED.salary_year_avg,
  job_posted_date = EXCLUDED.job_posted_date;
```

The key: staging table captures an immutable snapshot; `ON CONFLICT` ensures re-running the insert is safe. If you run this twice, the second run is a no-op.

## Notes

- **Timestamp traps:** Never use `CURRENT_TIMESTAMP` inside transformation logic; inject it as a parameter or reference an immutable `load_date` column from staging.
- **Soft deletes over hard deletes:** Use `is_deleted` flags and `effective_date` ranges instead of truncating. Enables audit trails and safer replays.
- **Immutable source snapshots:** Always land raw data with a surrogate `loaded_at` timestamp; regenerate transformations from that snapshot, never re-query live sources.
- **Reconcile before and after:** Before backfill, record counts and checksums (e.g., `COUNT(*), SUM(salary_year_avg)`) to catch silent data loss.
- **Related: Slowly Changing Dimensions (SCD):** Type 2 SCD (versioning with effective dates) is the formal pattern for replayable historical tracking; backfill strategy depends on which SCD type you choose.
