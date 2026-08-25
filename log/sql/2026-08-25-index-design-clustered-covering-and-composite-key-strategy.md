---
date: 2026-08-25
phase: sql
topic: Index design: clustered, covering and composite key strategy
---

# Index design: clustered, covering and composite key strategy

*SQL for analytics and engineering*

## Concept

An index is a sorted data structure that lets the database find rows without scanning every record. A **clustered index** determines the physical order of table rows—each table has at most one, usually on the primary key. A **covering index** includes all columns needed for a query, so the database never touches the main table (index-only scan). A **composite index** has multiple columns and works best when queries filter on the same column combinations repeatedly.

Index strategy matters most when tables grow large (millions+ rows) or queries run frequently in production. Without proper indexes, analytics queries full-table scan billions of rows, wasting CPU and I/O. A well-designed clustered index + covering index can reduce query time from seconds to milliseconds. The tradeoff: indexes slow writes (INSERT, UPDATE, DELETE) because the database must maintain them, so you design for read patterns, not every possible query.

Composite index column order is critical: put equality filters first (WHERE job_location = ...), then range filters (WHERE salary_year_avg > ...), then columns needed only for output. This follows the ESR rule—Equality, Sort/Range, Return.

## Practice

**Problem:** Analysts run this query 100 times per day to find remote junior roles by salary band:
```sql
SELECT job_id, job_title_short, salary_year_avg, job_posted_date
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_title_short = 'Junior Data Analyst'
  AND salary_year_avg BETWEEN 50000 AND 120000
ORDER BY job_posted_date DESC;
```

Design indexes to make this query efficient.

**Solution:**
```sql
-- Composite covering index: equality filters first, then range, then return columns
CREATE INDEX idx_remote_title_salary_covering
ON job_postings_fact(job_work_from_home, job_title_short, salary_year_avg, job_posted_date)
INCLUDE (job_id);

-- Alternatively, if the DBMS doesn't support INCLUDE (e.g., older MySQL):
CREATE INDEX idx_remote_title_salary_covering
ON job_postings_fact(job_work_from_home, job_title_short, salary_year_avg, job_posted_date, job_id);

-- Verify the plan uses index-only scan (or at least index seek + range scan, not table scan):
EXPLAIN (ANALYZE, BUFFERS)
SELECT job_id, job_title_short, salary_year_avg, job_posted_date
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_title_short = 'Junior Data Analyst'
  AND salary_year_avg BETWEEN 50000 AND 120000
ORDER BY job_posted_date DESC;
```

## Notes

- **Column order matters more than index count:** A single well-ordered composite index beats three single-column indexes. Put filters on low-cardinality columns first (job_work_from_home: 2 values) before high-cardinality ones (salary_year_avg: many values).
- **Watch for write amplification:** Each index you add slows INSERT/UPDATE/DELETE on that table. Profile write volume before adding 5 indexes; sometimes one covering index is enough.
- **Index-only scans are the goal:** If EXPLAIN shows "Index Scan" + "Table Scan," your index isn't covering—add missing columns to the INCLUDE clause or key list.
- **Clustered index choice is subtle:** In SQL Server, make the clustered index on a narrow, unique, ascending column (often surrogate PK). In PostgreSQL, this matters less; focus on covering indexes for analytics. Different DBMSs have different defaults.
- **Revisit: statistics, query hints, and plan caching** — indexes only work if the optimizer chooses them; stale statistics cause bad plans. Also learn how to read EXPLAIN output for your target database (EXPLAIN ANALYZE in PostgreSQL, SET STATISTICS IO ON in SQL Server).
