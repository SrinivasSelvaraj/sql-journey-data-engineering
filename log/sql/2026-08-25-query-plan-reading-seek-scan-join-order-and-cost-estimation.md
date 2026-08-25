---
date: 2026-08-25
phase: sql
topic: Query plan reading: seek, scan, join order and cost estimation
---

# Query plan reading: seek, scan, join order and cost estimation

*SQL for analytics and engineering*

## Concept

A query plan is the database optimizer's execution blueprint—it shows *how* the engine will retrieve and combine data, not just *what* data you asked for. The three critical components are **seek vs. scan** (how rows are located), **join order** (which tables are joined first), and **cost estimation** (predicted resource consumption in arbitrary units). Seeks use indexes to jump directly to relevant rows; scans read entire tables or index blocks sequentially. Join order matters enormously: joining a filtered small table to a large table is orders of magnitude faster than the reverse. Without understanding these, you write queries that syntactically work but execute in seconds instead of milliseconds.

Query plans become essential in production analytics when you're working with million-row tables or complex joins across multiple fact and dimension tables. A poorly ordered join can cause nested-loop operations that multiply row counts unnecessarily. Cost estimation (measured in relative units like I/O operations or CPU time) tells you which plan the optimizer chose and whether it's reasonable; if the estimated cost is wildly high, you've likely missed an index or written a query that confuses the optimizer.

## Practice

**Problem:** Write a query to find the average salary for remote data engineer roles posted in the last 90 days. Then reason about what access pattern the optimizer should use.

```sql
SELECT 
  AVG(salary_year_avg) AS avg_salary
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_title_short = 'Data Engineer'
  AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
  AND salary_year_avg IS NOT NULL;
```

**Plan reasoning:** Ideally, the optimizer should seek or scan on an index covering `(job_posted_date, job_work_from_home, job_title_short)` to filter rows efficiently, then compute the aggregate. If no composite index exists, it will full-scan the table and filter in-memory—acceptable for small tables, painful for millions of rows. The `IS NOT NULL` filter prevents division-by-zero errors in aggregation and may allow the optimizer to use a covering index that excludes NULLs.

## Notes

- **Seek vs. scan trade-off:** A seek is only faster than a scan if the index filters out >5–10% of rows; otherwise, the overhead of index navigation defeats the purpose.
- **Join order and cardinality:** Always join the most-filtered table first (smallest result set). Use `WHERE` filters aggressively before `JOIN` clauses to reduce cardinality early—the optimizer may not always get this right, especially with older statistics.
- **Cost units are relative, not absolute:** Comparing cost 500 to cost 5000 tells you which plan is cheaper, but neither number predicts wall-clock time; use `EXPLAIN ANALYZE` (PostgreSQL) or `SET STATISTICS IO ON` (SQL Server) to see actual rows and buffers touched.
- **Covering indexes:** An index that contains all columns needed for a query allows the optimizer to avoid table lookups entirely (index-only scan), dramatically cutting I/O.
- **Statistics decay:** Cardinality estimates grow stale as data changes; rerun `ANALYZE` or `UPDATE STATISTICS` regularly, especially after bulk loads, or the optimizer will make poor join-order decisions.
