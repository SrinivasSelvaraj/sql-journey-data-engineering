---
date: 2026-10-22
phase: sql
topic: Subquery vs CTE performance tradeoffs
---

# Subquery vs CTE performance tradeoffs

*SQL for analytics and engineering*

## Concept

A **subquery** is a query nested inside another query, executed inline at the point of reference. A **CTE (Common Table Expression)** using `WITH` creates a named, reusable result set defined before the main query. Both solve the same problem—breaking complex logic into readable steps—but differ critically in optimization and readability.

The optimizer treats them differently: **CTEs are materialized first** (computed once, stored temporarily), while **subqueries may be inlined** (merged into the outer query's execution plan). This means a CTE can be less efficient if the optimizer can't push predicates down, but more efficient if the same subquery is referenced multiple times (avoiding recalculation). Subqueries in `WHERE` clauses can block index usage and parallelization, whereas CTEs allow the optimizer to see the full query shape and make better decisions. Correlated subqueries—those referencing outer query columns—execute once per outer row, making them dangerous for performance at scale.

Choose CTEs for readability and when reusing logic; use subqueries sparingly, mainly in `SELECT` lists for single-row results. Always check the execution plan to confirm whether your query runs efficiently.

## Practice

**Problem:** Find the job title with the highest average salary, but only among jobs posted in the last 90 days and marked as remote-eligible. Show the title and average salary.

```sql
-- Using CTE (preferred for clarity + reusability)
WITH recent_remote_jobs AS (
  SELECT 
    job_title_short,
    salary_year_avg,
    job_posted_date
  FROM job_postings_fact
  WHERE job_work_from_home = TRUE
    AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
    AND salary_year_avg IS NOT NULL
)
SELECT 
  job_title_short,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary
FROM recent_remote_jobs
GROUP BY job_title_short
ORDER BY avg_salary DESC
LIMIT 1;
```

## Notes

- **Correlated subqueries are a performance trap:** `SELECT * FROM jobs j1 WHERE salary > (SELECT AVG(salary) FROM jobs j2 WHERE j2.department = j1.department)` runs the subquery millions of times. Use a `JOIN` or CTE instead.
- **Multiple references favor CTEs:** If you reference the same logic twice, a CTE ensures single computation; nested subqueries compute each time.
- **Subqueries in `FROM` must be aliased:** `FROM (SELECT ...) AS subquery_name` is required syntax; forgetting the alias causes parse errors.
- **CTEs and window functions are complementary:** Use `WITH` to stage a window function result, then filter or aggregate again in the outer query without nesting complexity.
- **Always validate with `EXPLAIN PLAN`:** Theory matters less than actual execution; different databases (Postgres, Snowflake, BigQuery) optimize CTEs differently—some materialize, others inline automatically.
