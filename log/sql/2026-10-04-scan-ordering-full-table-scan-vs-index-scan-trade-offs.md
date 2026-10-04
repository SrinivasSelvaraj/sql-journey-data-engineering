---
date: 2026-10-04
phase: sql
topic: Scan ordering: full table scan vs index scan trade-offs
---

# Scan ordering: full table scan vs index scan trade-offs

*SQL for analytics and engineering*

## Concept

A **full table scan** reads every row in a table sequentially; an **index scan** uses a B-tree or similar structure to locate rows matching a predicate, then retrieves only those rows. The trade-off depends on selectivity: if you're filtering 90% of rows, an index scan is dramatically faster; if you're keeping 95% of rows, the sequential I/O of a full scan often wins because index lookups add overhead.

The database optimizer chooses based on table size, index presence, filter cardinality, and whether the index covers your SELECT columns (a covering index avoids the second lookup back to the table). Without understanding this trade-off, you might write queries that *look* correct but scan millions of rows unnecessarily, or create indexes that go unused because the optimizer predicts a full scan is cheaper.

Practical signal: if a query on a 100M-row table takes 30 seconds, check the query plan. Full table scans on large tables with tight filters are red flags. Conversely, if you're aggregating 95% of a table, adding an index on the filter column may not help—the optimizer will full-scan anyway.

## Practice

**Problem:** You have 2M job postings. Find all remote jobs posted in the last 90 days with salary > $150k, and return job_id, title, and salary. Write an efficient query and explain why the execution plan matters.

```sql
-- Suboptimal: may full-scan if salary is not indexed
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_work_from_home = true
  AND salary_year_avg > 150000
  AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days';

-- Optimal: composite index on (job_posted_date, salary_year_avg, job_work_from_home)
-- or at minimum (job_posted_date) if most postings are recent
CREATE INDEX idx_recent_remote_salary 
  ON job_postings_fact(job_posted_date DESC, salary_year_avg DESC)
  WHERE job_work_from_home = true;

SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_work_from_home = true
  AND salary_year_avg > 150000
  AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days';
```

**Why:** The date filter is likely most selective (recent postings are fewer). A composite index on `(job_posted_date, salary_year_avg)` with a partial index on `WHERE job_work_from_home = true` lets the optimizer seek to the date range, then scan within that narrow band. Without it, the DB may scan all 2M rows.

## Notes

- **Common mistake:** Creating an index on every filter column independently. The order matters—lead with the most selective column, or one that bounds the search space (dates, ranges). Trailing equality columns (like `job_work_from_home`) belong at the end or in a `WHERE` clause of a partial index.

- **Partial indexes** are underutilized: `WHERE job_work_from_home = true` reduces index size and search cost when that condition is always present in your queries.

- **Index covers** your query if it includes all columns in SELECT and WHERE—no table lookup needed. Add `INCLUDE (job_title_short, salary_year_avg)` in some systems (SQL Server, PostgreSQL 11+) to avoid double lookups.

- **EXPLAIN ANALYZE is your friend:** Always run `EXPLAIN (ANALYZE, BUFFERS)` in PostgreSQL or equivalent to confirm you're using an index. A "Seq Scan" on a 2M-row table with a tight filter is often a sign the planner chose wrong or your index is missing.

- **Revisit:** Cost-based optimizer heuristics, join ordering, and statistics freshness—stale row counts can trick the optimizer into picking full scans when an index would win.
