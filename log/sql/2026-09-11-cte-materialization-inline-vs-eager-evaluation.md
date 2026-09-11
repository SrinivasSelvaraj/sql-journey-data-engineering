---
date: 2026-09-11
phase: sql
topic: CTE materialization: inline vs eager evaluation
---

# CTE materialization: inline vs eager evaluation

*SQL for analytics and engineering*

## Concept

A Common Table Expression (CTE) can be evaluated in two ways: **inline** (the CTE's query is merged into the outer query, executed once per reference) or **eager** (materialized into a temporary result set once, then reused). Most SQL engines default to inline evaluation for simplicity, but this can cause the same subquery to execute multiple times or produce inefficient plans when the CTE is referenced more than once or contains expensive operations.

Understanding when your database materializes a CTE matters because it directly affects query performance. If a CTE is expensive (e.g., involves joins, aggregations, or window functions) and is referenced multiple times, you want eager evaluation to compute it once. Conversely, simple CTEs (filtering a single table) may execute faster inline because materialization adds I/O overhead. Without awareness of this, you might write a query that looks clean but runs slowly, or fail to recognize why the same CTE reference in different branches of a UNION behaves differently.

Most modern engines (PostgreSQL, BigQuery, Snowflake, DuckDB) offer hints or configuration to control materialization. PostgreSQL uses `MATERIALIZED` / `NOT MATERIALIZED` keywords; BigQuery defaults to inline and offers `WITH ... AS (SELECT ...)` optimization hints; Snowflake optimizes automatically. The key insight: **test your query plan** to confirm whether the CTE executed once or multiple times, especially in production scenarios where data volume exposes inefficiency.

## Practice

**Problem:** You need to find the top-paying remote jobs and compare their average salary to the overall average. Write a query using a CTE for the remote jobs subset. The CTE will be referenced twice (once for filtering, once for comparison), so you want to ensure it's materialized efficiently.

```sql
WITH remote_jobs AS MATERIALIZED (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_posted_date
  FROM job_postings_fact
  WHERE job_work_from_home = TRUE
    AND salary_year_avg IS NOT NULL
)
SELECT 
  rj.job_title_short,
  rj.salary_year_avg,
  ROUND(AVG(rj.salary_year_avg) OVER (), 2) AS avg_remote_salary,
  ROUND(
    (SELECT AVG(salary_year_avg) FROM job_postings_fact 
     WHERE salary_year_avg IS NOT NULL), 
    2
  ) AS overall_avg_salary,
  ROUND(rj.salary_year_avg - (SELECT AVG(salary_year_avg) FROM job_postings_fact 
                              WHERE salary_year_avg IS NOT NULL), 2) AS diff_vs_overall
FROM remote_jobs rj
ORDER BY rj.salary_year_avg DESC
LIMIT 10;
```

The `MATERIALIZED` keyword (PostgreSQL syntax) ensures `remote_jobs` is computed once and stored, avoiding re-execution of the WHERE clause. In BigQuery or Snowflake, test the query plan to confirm the CTE is not inlined unnecessarily.

## Notes

- **Inline traps:** A CTE referenced in a subquery inside a WHERE clause may be re-evaluated for each outer row if inlined; materialization forces a single execution, then a join or hash lookup. Always check EXPLAIN plans.
- **Size matters:** Materializing a massive CTE into temp storage can be slower than inline evaluation for small result sets. Profile before assuming materialization is better.
- **Window functions & aggregates:** CTEs containing `GROUP BY`, `HAVING`, or window functions are usually worth materializing because recomputing them is expensive; simple filters often aren't.
- **Vendor-specific syntax:** PostgreSQL uses `MATERIALIZED / NOT MATERIALIZED`; BigQuery and Snowflake use query hints or rely on query optimizer heuristics. Know your database's defaults and tuning knobs.
- **Related:** Query optimization, execution plans (EXPLAIN), temporary tables vs. CTEs, recursion in CTEs (always materialized), and cost-based optimizer behavior in your target database.
