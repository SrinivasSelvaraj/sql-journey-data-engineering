---
date: 2026-08-08
phase: sql
topic: Index design and column order
---

# Index design and column order

*SQL for analytics and engineering*

## Concept

Index column order determines query performance when filtering, joining, or sorting. The optimal order follows the **access pattern**: leading columns should match the WHERE clause predicates in order of selectivity, then join columns, then sort columns. A composite index on `(job_location, salary_year_avg)` accelerates a query filtering by location first, but performs poorly if you filter only by salary—the database cannot skip the first column.

Without intentional index design, even small tables suffer full scans; medium tables (millions of rows) become unusable. The database optimizer can only use an index prefix: if you have an index on `(A, B, C)`, it efficiently supports queries filtering on `A`, or `A AND B`, or `A AND B AND C`, but not queries filtering on `B AND C` alone or `C` alone.

Column order also interacts with storage: keeping narrow columns early (dates, booleans, small integers) before wide columns (text, decimals) reduces the index size and improves cache locality. On some databases, clustered indexes (the table's physical sort order) can eliminate the need for separate indexes entirely if they match your most common access pattern.

## Practice

**Problem:** You run frequent queries filtering jobs by location and then by salary range, and you need to count results grouped by whether the role is remote. Your current query scans 50M rows and takes 12 seconds.

```sql
-- Slow: full table scan or poor index use
SELECT job_work_from_home, COUNT(*) AS count
FROM job_postings_fact
WHERE job_location = 'San Francisco, CA'
  AND salary_year_avg BETWEEN 100000 AND 200000
GROUP BY job_work_from_home;

-- Solution: composite index matching filter order, then include remote flag
CREATE INDEX idx_job_postings_location_salary 
ON job_postings_fact(job_location, salary_year_avg, job_work_from_home);

-- Now the query uses index range scan, not full table scan
-- Database finds rows by location first, narrows by salary, then reads remote flag
```

## Notes

- **Column order vs. selectivity:** Put the most selective filter first *only if* it's also your most frequent access pattern; otherwise, prioritize the actual query order to enable index range scans.
- **Index-only scans:** Include non-filtered columns (like `job_work_from_home`) in the index's INCLUDE clause (SQL Server) or as part of the key if they cover your SELECT list; this lets the database read the answer without touching the main table.
- **Clustered vs. non-clustered:** The clustered index defines physical row order; every query benefits from one optimal clustered index, but multiple non-clustered indexes can support different access patterns—choose the clustered index for your hottest query path.
- **Over-indexing overhead:** Each additional index slows INSERT/UPDATE/DELETE; audit whether an index is actually used (use `sys.dm_db_index_usage_stats` in SQL Server) before adding it.
- **Nearby topic—statistics:** Indexes are only useful if the query optimizer has up-to-date column statistics; stale stats cause the optimizer to ignore an index or choose the wrong one.
