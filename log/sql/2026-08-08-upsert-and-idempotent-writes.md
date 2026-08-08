---
date: 2026-08-08
phase: sql
topic: UPSERT and idempotent writes
---

# UPSERT and idempotent writes

*SQL for analytics and engineering*

## Concept

An **UPSERT** (UPDATE + INSERT) is a single operation that inserts a new row if it doesn't exist, or updates an existing row if it does—all in one atomic statement. In data engineering, this is critical because data pipelines often re-run or receive late-arriving data. Without idempotent writes, you risk duplicate records, inflated metrics, or orphaned state.

**Idempotency** means running the same operation multiple times produces the same result as running it once. For analytics, this is essential: if your ETL job crashes and retries, you need confidence that re-processing yesterday's job postings won't double-count them or leave inconsistent timestamps. UPSERT enforces this by making the write operation deterministic based on a key.

In practice, UPSERT breaks down when: (1) you lack a natural or surrogate primary key to identify "same" records, (2) your database doesn't support the syntax (older MySQL, some warehouses), or (3) you try to UPSERT without a proper key constraint, leading to duplicates anyway. Understanding query plans here matters because UPSERT performance hinges on index lookups during the INSERT/UPDATE decision.

## Practice

**Problem:** You receive a daily batch of job postings. Some are new; some are updates to existing postings (same `job_id` but revised salary or location). Write an idempotent operation that ensures each `job_id` appears exactly once in `job_postings_fact`, with the latest data.

```sql
INSERT INTO job_postings_fact (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM staging_job_postings
ON CONFLICT(job_id) DO UPDATE SET
  job_title_short = EXCLUDED.job_title_short,
  salary_year_avg = EXCLUDED.salary_year_avg,
  job_work_from_home = EXCLUDED.job_work_from_home,
  job_posted_date = EXCLUDED.job_posted_date,
  job_location = EXCLUDED.job_location;
```

(PostgreSQL syntax. For MySQL 8.0+, use `ON DUPLICATE KEY UPDATE`. For Snowflake/BigQuery, use `MERGE` statement.)

## Notes

- **Missing PRIMARY KEY or UNIQUE constraint:** UPSERT relies on a key to detect conflicts. Without one defined, the operation either fails or silently creates duplicates. Always verify constraints exist before writing UPSERT logic.
- **EXCLUDED keyword (PostgreSQL) vs. VALUES():** Different databases expose rejected rows differently; know your dialect's syntax to avoid subtle bugs where old values persist.
- **Partial updates:** Only update columns that can change; leave immutable columns (e.g., `job_posted_date` if it's the creation timestamp) alone or you'll overwrite historical truth.
- **Performance consideration:** UPSERT scans the index on the conflict key for every row. On large fact tables, batching many rows in one UPSERT is faster than many small UPSERT statements.
- **Adjacent concept—SCD Type 1 vs. Type 2:** UPSERT is Type 1 (overwrite history). If you need to track all versions of a job posting, you'll need Type 2 (add new row with effective dates) instead, requiring different logic entirely.
