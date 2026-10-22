---
date: 2026-10-22
phase: sql
topic: Index selection and query optimizer hints
---

# Index selection and query optimizer hints

*SQL for analytics and engineering*

## Concept

An index is a data structure that enables the query optimizer to locate rows faster than scanning the entire table. Without indexes, every query performs a full table scan—reading every row sequentially. Indexes become critical when filtering on non-primary key columns or joining large tables; a well-chosen index can reduce query time from seconds to milliseconds.

Query optimizer hints are directives that override the optimizer's default plan choice. Most modern databases (PostgreSQL, MySQL, SQL Server) have cost-based optimizers that estimate which plan is fastest; hints force a specific approach (e.g., join method, index usage). Hints are a last resort—only when the optimizer chooses poorly despite statistics being current—but essential knowledge for interviews and production firefighting.

Index selection fails when: columns used in WHERE, JOIN, and ORDER BY clauses lack indexes; when the optimizer chooses a sequential scan over an available index due to outdated statistics; or when a composite index isn't structured to match query patterns. Without understanding query plans (EXPLAIN in PostgreSQL/MySQL, EXPLAIN PLAN in Oracle), you're flying blind.

## Practice

**Problem:** You're analyzing job postings and notice queries filtering by `job_work_from_home` and `job_posted_date` run slowly. Write a solution including index creation and a query with an optimizer hint to force index usage.

```sql
-- Create a composite index on the two most-filtered columns
CREATE INDEX idx_remote_posted 
ON job_postings_fact(job_work_from_home, job_posted_date DESC);

-- Query with optimizer hint (PostgreSQL syntax using /*+ INDEX */)
-- For MySQL, use FORCE INDEX; for SQL Server, use WITH (INDEX=...)
EXPLAIN ANALYZE
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_posted_date >= '2024-01-01'
ORDER BY job_posted_date DESC
LIMIT 100;

-- If optimizer still ignores the index, force it (PostgreSQL example):
SET enable_seqscan = OFF;
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_posted_date >= '2024-01-01'
ORDER BY job_posted_date DESC
LIMIT 100;
```

## Notes

- **Composite index order matters**: place high-cardinality, low-selectivity columns first (e.g., `job_posted_date` before `job_work_from_home`), unless ORDER BY demands otherwise; test with EXPLAIN.
- **Over-indexing is costly**: every INSERT/UPDATE/DELETE must maintain indexes; index bloat slows writes. Index only columns actually queried.
- **Optimizer hints are a smell**: if you need hints repeatedly, investigate stale statistics (ANALYZE table), missing indexes, or schema design; hints break after schema changes and obscure root cause.
- **EXPLAIN output is your friend**: learn to read cost estimates, seq scans vs. index scans, and actual vs. planned rows; a mismatch signals stale stats or bad estimates.
- **Adjacent topics**: covering indexes (include all query columns to avoid table lookup), partial indexes (WHERE condition baked in for common filters), and statistics maintenance (ANALYZE, auto-vacuum) are essential follow-ups.
