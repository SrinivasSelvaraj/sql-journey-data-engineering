---
date: 2026-08-06
phase: sql
topic: Correlated subqueries and when the optimiser rewrites them
---

# Correlated subqueries and when the optimiser rewrites them

*SQL for analytics and engineering*

## Concept

A correlated subquery is a subquery that references columns from the outer query. Unlike a normal subquery that executes once, a correlated subquery executes once for *each row* of the outer query, making it a potential performance trap. The database optimizer sometimes rewrites them into joins or window functions automatically, but this rewrite is not guaranteed—and when it doesn't happen, you can end up scanning a table millions of times.

The practical distinction: `SELECT * FROM postings p1 WHERE salary_year_avg > (SELECT AVG(salary_year_avg) FROM postings p2 WHERE p2.job_location = p1.job_location)` must re-evaluate the subquery for every distinct job location in the outer table. If your table has 500,000 rows across 5,000 locations, you've potentially triggered 5,000 separate aggregate scans instead of one.

Correlated subqueries matter most in WHERE and SELECT clauses. Modern optimizers (PostgreSQL, BigQuery, Snowflake) handle them well in WHERE with semi-joins; they stumble more often in SELECT clauses (scalar subqueries) where rewriting is harder. The key: if your query plan shows a nested loop with dependent lookups, you've found a performance cliff.

## Practice

**Problem:** Find all job postings where the salary is above the average salary for that specific job title. Return job_id, job_title_short, salary_year_avg, and the average salary for comparison.

```sql
-- Correlated subquery (may or may not be optimized)
SELECT 
  p1.job_id,
  p1.job_title_short,
  p1.salary_year_avg,
  (SELECT AVG(p2.salary_year_avg) 
   FROM job_postings_fact p2 
   WHERE p2.job_title_short = p1.job_title_short) AS title_avg_salary
FROM job_postings_fact p1
WHERE p1.salary_year_avg > 
  (SELECT AVG(p3.salary_year_avg) 
   FROM job_postings_fact p3 
   WHERE p3.job_title_short = p1.job_title_short);

-- Better: rewrite using window function (guaranteed single pass)
WITH salary_stats AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    AVG(salary_year_avg) OVER (PARTITION BY job_title_short) AS title_avg_salary
  FROM job_postings_fact
)
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  title_avg_salary
FROM salary_stats
WHERE salary_year_avg > title_avg_salary;
```

## Notes

- **Optimizer dependency**: Never assume the optimizer rewrites your correlated subquery—check the actual query plan (EXPLAIN in PostgreSQL/MySQL, EXPLAIN PLAN in Oracle, query plan in Snowflake/BigQuery). A nested loop join is your signal to refactor.

- **Window functions are the replacement**: When you see `OVER (PARTITION BY ...)`, you're expressing "calculate per group" in a way the optimizer handles in a single pass. This is almost always faster than correlated subqueries in SELECT or WHERE clauses.

- **EXISTS vs. IN**: Correlated EXISTS subqueries (`WHERE EXISTS (SELECT 1 FROM...)`) often optimize to semi-joins better than correlated scalar subqueries. EXISTS is a common exception where the correlation doesn't always hurt performance.

- **Scalar subquery caching**: Some optimizers (particularly Snowflake) cache scalar correlated subquery results within a query execution, reducing redundant evaluations—but this is an implementation detail, not a guarantee.

- **Interview note**: Mention that you'd use `EXPLAIN` to validate performance; saying "I'd rewrite to a window function or join to avoid potential O(n²) behavior" signals you think about query plans before execution.
