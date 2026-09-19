---
date: 2026-09-19
phase: pipelines
topic: CQRS: command and query responsibility separation
---

# CQRS: command and query responsibility separation

*Pipelines and orchestration*

## Concept

CQRS separates read and write operations into distinct models and services, preventing a single code path from being optimized for both simultaneously. In data pipelines, this means your ingestion logic (commands: INSERT, UPDATE, DELETE) should not share schema or optimization with your analytics queries (queries: SELECT aggregations, joins, filters). Commands need fast writes, idempotency, and audit trails; queries need denormalization, indexing, and materialized views.

Without CQRS separation, you either accept slow analytical queries that lock write operations, or you sacrifice data consistency and traceability to chase query speed. You end up adding indexes that slow inserts, denormalizing source tables that compromise update safety, or writing custom retry logic that pollutes business logic. The pipeline fails silently—query results look stale but you don't know why, or an upsert hangs the warehouse.

In orchestration, CQRS means your pipeline tasks should have distinct "write" tasks (load, transform, insert) that validate inputs and handle retries, and separate "read" tasks (quality checks, reporting, downstream feeds) that only consume committed state. This boundary is what lets you rerun safely: you know exactly what writes are idempotent and what reads are side-effect-free.

## Practice

**Problem:** Your job_postings_fact table serves both nightly ETL upserts (millions of new postings, salary updates) and real-time dashboard queries (filter by location and salary, group by job_title_short). Upserts lock the table during the day; dashboards time out. You're tempted to add a summary table, but you're not sure what queries to optimize for.

**Solution:** Separate write and read models.

```sql
-- WRITE MODEL: normalized, audit-focused, optimized for idempotent upsert
CREATE TABLE job_postings_write (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR,
  salary_year_avg DECIMAL,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR,
  updated_at TIMESTAMP NOT NULL,
  data_hash VARCHAR NOT NULL -- for idempotency detection
);

-- READ MODEL: denormalized, aggregated, refreshed on schedule
CREATE TABLE job_postings_analytics (
  job_location VARCHAR,
  job_title_short VARCHAR,
  salary_avg DECIMAL,
  salary_p50 DECIMAL,
  salary_p95 DECIMAL,
  posting_count INT,
  pct_remote DECIMAL,
  refreshed_at TIMESTAMP,
  PRIMARY KEY (job_location, job_title_short)
);
CREATE INDEX idx_job_postings_analytics_location ON job_postings_analytics(job_location);
CREATE INDEX idx_job_postings_analytics_title ON job_postings_analytics(job_title_short);

-- ETL task 1: WRITE (idempotent, transaction-safe)
MERGE INTO job_postings_write w
USING staging_postings s
  ON w.job_id = s.job_id
WHEN MATCHED AND w.data_hash != s.data_hash THEN
  UPDATE SET salary_year_avg = s.salary_year_avg, updated_at = NOW()
WHEN NOT MATCHED THEN
  INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, 
          job_posted_date, job_location, updated_at, data_hash)
  VALUES (s.job_id, s.job_title_short, s.salary_year_avg, s.job_work_from_home, 
          s.job_posted_date, s.job_location, NOW(), s.data_hash);

-- ETL task 2: READ (runs after write, can be materialized or incremental)
TRUNCATE TABLE job_postings_analytics;
INSERT INTO job_postings_analytics
SELECT 
  job_location,
  job_title_short,
  AVG(salary_year_avg) as salary_avg,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) as salary_p50,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY salary_year_avg) as salary_p95,
  COUNT(*) as posting_count,
  SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END)::FLOAT / COUNT(*) as pct_remote,
  NOW() as refreshed_at
FROM job_postings_write
GROUP BY job_location, job_title_short;
```

Dashboards now query `job_postings_analytics` (fast, indexed); ETL writes to `job_postings_write` (safe, auditable). Rerun the write task: idempotency check via data_hash prevents duplicates. If read task fails, write state is clean; if write fails, analytics stays stale but consistent.

## Notes

- **Mistake:** Confusing CQRS with microservices. You
