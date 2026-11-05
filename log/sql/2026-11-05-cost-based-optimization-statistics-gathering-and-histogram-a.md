---
date: 2026-11-05
phase: sql
topic: Cost-based optimization: statistics gathering and histogram accuracy
---

# Cost-based optimization: statistics gathering and histogram accuracy

*SQL for analytics and engineering*

## Concept

Cost-based optimizers rely on table and column statistics—row counts, cardinality, value distributions, and NULL counts—to estimate execution costs and choose between competing plans (nested loops vs. hash join vs. sort-merge, scan vs. seek, etc.). When statistics are stale, missing, or inaccurate, the optimizer makes poor guesses: it may choose a full table scan when an index seek would be faster, or build a hash table for the wrong side of a join. Histogram accuracy is especially critical for range predicates and inequality filters; a skewed salary distribution or clustered job_posted_date values can cause the optimizer to vastly overestimate or underestimate rows passing through a filter.

Gathering statistics is a maintenance operation: you run it after bulk loads, schema changes, or when you notice query performance degrading without code changes. Different engines have different commands (ANALYZE in PostgreSQL, ANALYZE TABLE in MySQL, UPDATE STATISTICS in SQL Server, DBMS_STATS in Oracle). Histograms capture frequency distributions; without them, the optimizer assumes uniform distribution and can be wildly wrong on selective predicates.

In interview and production settings, you may inherit slow queries that are actually caused by stale statistics rather than bad SQL. Reasoning about a query plan requires understanding what the optimizer *believed* about data distribution at compile time—row estimates at each step—and whether those beliefs match reality. If estimated rows are orders of magnitude off, statistics are usually the culprit.

## Practice

**Problem:** A query joining job_postings_fact to itself (to find similar jobs by salary band) is using nested-loop instead of a hash join, making it extremely slow. You suspect the optimizer underestimated the number of rows in the salary range filter. Write a query that would expose the problem and then rebuild statistics.

```sql
-- First, check the cardinality estimate vs. actual for a salary band
SELECT 
  salary_year_avg,
  COUNT(*) AS actual_count
FROM job_postings_fact
WHERE salary_year_avg BETWEEN 100000 AND 150000
GROUP BY salary_year_avg
ORDER BY actual_count DESC;

-- The slow join query (simplified)
EXPLAIN ANALYZE
SELECT 
  a.job_id,
  b.job_id,
  a.salary_year_avg
FROM job_postings_fact a
INNER JOIN job_postings_fact b
  ON a.salary_year_avg = b.salary_year_avg
  AND a.job_id < b.job_id
WHERE a.salary_year_avg BETWEEN 100000 AND 150000;

-- Rebuild statistics (PostgreSQL syntax; adjust for your engine)
ANALYZE job_postings_fact;

-- Or, more aggressive refresh in MySQL:
ANALYZE TABLE job_postings_fact;

-- Re-run EXPLAIN ANALYZE to compare plans and row estimates
EXPLAIN ANALYZE
SELECT 
  a.job_id,
  b.job_id,
  a.salary_year_avg
FROM job_postings_fact a
INNER JOIN job_postings_fact b
  ON a.salary_year_avg = b.salary_year_avg
  AND a.job_id < b.job_id
WHERE a.salary_year_avg BETWEEN 100000 AND 150000;
```

## Notes

- **EXPLAIN vs. EXPLAIN ANALYZE**: EXPLAIN shows estimated row counts and chosen operators; EXPLAIN ANALYZE (or ACTUAL PLAN in SQL Server) runs the query and shows *actual* counts. Always compare both to diagnose stale stats.
- **Skew and multi-column histograms**: A single column's histogram may not capture correlation; if job_location and salary_year_avg are correlated, a naive histogram on salary alone will mislead the optimizer on filtered joins.
- **When to refresh**: After bulk INSERT/UPDATE/DELETE (especially >10% of table), after index creation that changes selectivity, or on a schedule (nightly/weekly for OLTP, weekly/monthly for data warehouse). Monitor query performance regression as a leading indicator.
- **Manual hints vs. statistics**: Optimizer hints (FORCE INDEX, /*+ BKA() */ in MySQL) can override bad plans, but they're a band-aid; fixing root-cause statistics is more sustainable.
- **Adjacent topics**: Connects to query plan interpretation, index selection strategy, and cardinality estimation errors; revisit when you see "rows estimated=10 actual=10000000" in EXPLAIN output.
