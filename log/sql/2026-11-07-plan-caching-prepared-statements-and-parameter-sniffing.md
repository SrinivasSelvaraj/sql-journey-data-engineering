---
date: 2026-11-07
phase: sql
topic: Plan caching: prepared statements and parameter sniffing
---

# Plan caching: prepared statements and parameter sniffing

*SQL for analytics and engineering*

## Concept

**Prepared statements** are SQL queries with placeholders (`?` or named parameters) that are compiled once and executed multiple times with different parameter values. The database parses, optimizes, and generates a query plan at preparation time, then reuses that plan for each execution. This separation eliminates redundant parsing overhead and provides protection against SQL injection.

**Parameter sniffing** occurs when the query optimizer uses the *first* set of parameter values to generate the execution plan, then applies that same plan to all subsequent executions—even when later parameter values would benefit from a different plan. This is most dangerous with highly skewed data distributions: a query optimized for `WHERE region = 'US'` (90% of rows) may become catastrophically slow when run with `WHERE region = 'Antarctica'` (3 rows), because the optimizer chose a full table scan instead of an index seek.

Without prepared statements, you reparse and replan on every execution, wasting CPU. Without awareness of parameter sniffing, you get query regressions in production where a parameter value you never tested causes the cached plan to degrade performance by orders of magnitude. The fix is either forcing plan recompilation, using query hints, or restructuring the logic to avoid parameter-dependent cardinality estimates.

## Practice

**Problem:** You're writing a job search API endpoint. A user can filter by `job_title_short` and `salary_year_avg`. Initial tests with `job_title_short = 'Data Analyst'` are fast (100k rows). But when a rare title like `'Underwater Basket Weaver'` is queried (2 rows), the query becomes slow because the optimizer's first-run plan assumed high cardinality.

Demonstrate a prepared statement approach and explain how you'd mitigate parameter sniffing.

```sql
-- Prepared statement with parameter sniffing risk
PREPARE search_jobs (VARCHAR, NUMERIC) AS
  SELECT job_id, job_title_short, salary_year_avg, job_location
  FROM job_postings_fact
  WHERE job_title_short = $1
    AND salary_year_avg >= $2
  ORDER BY salary_year_avg DESC;

-- First execution (caches plan for high-cardinality 'Data Analyst')
EXECUTE search_jobs('Data Analyst', 80000);

-- Later execution (reuses plan, now suboptimal for rare title)
EXECUTE search_jobs('Underwater Basket Weaver', 80000);

-- Mitigation: Force recompile or use local variable assignment
-- Option 1: Explicit recompile hint (SQL Server)
-- OPTION (RECOMPILE) in the query

-- Option 2: Local variable assignment to break parameter sniffing
PREPARE search_jobs_safe (VARCHAR, NUMERIC) AS
  DECLARE @title VARCHAR = $1;
  DECLARE @min_salary NUMERIC = $2;
  SELECT job_id, job_title_short, salary_year_avg, job_location
  FROM job_postings_fact
  WHERE job_title_short = @title
    AND salary_year_avg >= @min_salary
  ORDER BY salary_year_avg DESC;
```

## Notes

- **Parameter sniffing is database-specific**: SQL Server and Oracle cache plans aggressively and suffer most; PostgreSQL is less vulnerable but still possible. Always test with realistic data distributions, not just happy-path values.

- **"Atypical value" trap**: The first query execution can poison the plan for all subsequent executions. Run performance tests with multiple realistic parameter sets *before* deploying, not just the common case.

- **Connects to execution plans**: Learn `EXPLAIN` / `EXPLAIN ANALYZE` to inspect whether the optimizer is using an index seek (good for rare values) or table scan (appropriate for high cardinality). Query plan analysis reveals when parameter sniffing has occurred.

- **Locality of reference**: Prepared statements also improve cache locality on the database side—reducing memory churn and CPU stalls. The performance win is not just from eliminating parse overhead; it's cumulative across parsing, optimization, and buffer management.

- **Revisit when**: You encounter production query slowdowns after deploying code that worked in testing, or when the same query is slow "sometimes." These are classic parameter sniffing symptoms. Also revisit when optimizing high-volume OLTP workloads where prepared statement reuse compounds.
