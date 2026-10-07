---
date: 2026-10-07
phase: python
topic: Bulk operations and batch insert optimization
---

# Bulk operations and batch insert optimization

*Python for data engineering*

## Concept

Bulk operations and batch insert optimization are techniques for loading large volumes of data efficiently by grouping individual inserts into single transactions or using database-native bulk loaders. Instead of executing `INSERT` statements one row at a time, you collect rows into batches—typically 1,000–10,000 rows—and insert them together. This matters because single-row inserts create per-row overhead: connection handshakes, query parsing, index updates, and transaction commits multiply the wall-clock time. A naive loop inserting 1 million rows one-by-one might take hours; batched inserts of the same data take minutes.

Without batching, pipelines become I/O-bound bottlenecks. Your database spends more time managing transaction state than moving data. More critically, bad input handling breaks during bulk operations: a single malformed row in a 5,000-row batch can fail the entire batch, requiring retry logic and partial rollback strategies. Typed, validated input ensures that batches either succeed atomically or fail predictably, not somewhere in between.

## Practice

**Problem:** Load 500,000 job postings into `job_postings_fact`, validating that `salary_year_avg` is non-negative, `job_posted_date` is not in the future, and `job_location` is not null. Avoid inserting invalid rows while minimizing transaction overhead.

```sql
-- Batch insert with data validation (PostgreSQL example)
INSERT INTO job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM (VALUES 
  ('jp_1001', 'Data Engineer', 125000, true, '2024-01-15', 'Remote'),
  ('jp_1002', 'Analytics Engineer', 110000, false, '2024-01-16', 'New York, NY'),
  ('jp_1003', 'SQL Developer', 95000, true, '2024-01-17', 'San Francisco, CA')
  -- ... up to N rows per batch
) AS batch(job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
WHERE 
  salary_year_avg >= 0
  AND job_posted_date <= CURRENT_DATE
  AND job_location IS NOT NULL
ON CONFLICT (job_id) DO NOTHING;
```

## Notes

- **Batch size tuning:** Start with 1,000–5,000 rows per batch; measure latency vs. memory usage. Too small = wasted overhead; too large = memory pressure and harder error isolation.
- **Validation before insert:** Filter/validate rows in application code (Python dataclass, Pydantic) before batching; rejecting bad rows pre-flight prevents partial batch failures and simplifies rollback logic.
- **Connection pooling + transactions:** Batch inserts must run within a single transaction to ensure atomicity. Use connection pooling (psycopg2, SQLAlchemy) to avoid connection exhaustion across many batches.
- **Adjacent topics:** Dead letter queues (capture rejected rows for manual review), idempotency keys (`ON CONFLICT`), and incremental loading patterns (checkpoints per batch) all build on bulk operation architecture.
- **Testability:** Mock batches with small fixtures (5–10 rows) for unit tests; use temporary tables for integration tests to avoid polluting production data and enable rapid rollback.
