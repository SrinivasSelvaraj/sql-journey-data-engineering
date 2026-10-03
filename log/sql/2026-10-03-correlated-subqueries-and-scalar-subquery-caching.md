---
date: 2026-10-03
phase: sql
topic: Correlated subqueries and scalar subquery caching
---

# Correlated subqueries and scalar subquery caching

*SQL for analytics and engineering*

## Concept

A **correlated subquery** references columns from the outer query, executing once per outer row rather than once total. This differs from a regular subquery (independent, executes once). Correlated subqueries are powerful for row-by-row comparisons—finding employees earning more than their department average, or jobs posted after a certain threshold—but they're computationally expensive because each outer row triggers a full subquery evaluation.

**Scalar subquery caching** is an optimizer behavior (especially in PostgreSQL, MySQL 8.0+) where the database caches results of deterministic scalar subqueries to avoid redundant computation. If a correlated subquery references only outer columns that don't change within a batch of rows, the optimizer may recognize this and reuse cached results. Without this optimization, a correlated subquery on a million-row table can execute a million times, degrading performance catastrophically.

The practical tension: correlated subqueries are intuitive and sometimes unavoidable, but they can turn a millisecond query into a multi-second nightmare. Understanding when the optimizer will cache (or when you should rewrite to `JOIN` or window functions) is essential for writing performant production SQL. Always check the query plan.

## Practice

**Problem:** Find all job postings where the salary is above the average salary for that job title. Return job_id, job_title_short, and salary_year_avg.

```sql
SELECT 
  job_id,
  job_title_short,
  salary_year_avg
FROM job_postings_fact j1
WHERE salary_year_avg > (
  SELECT AVG(salary_year_avg)
  FROM job_postings_fact j2
  WHERE j2.job_title_short = j1.job_title_short
    AND j2.salary_year_avg IS NOT NULL
)
ORDER BY job_title_short, salary_year_avg DESC;
```

**Better (non-correlated, using window function):**

```sql
SELECT 
  job_id,
  job_title_short,
  salary_year_avg
FROM (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    AVG(salary_year_avg) OVER (PARTITION BY job_title_short) AS title_avg
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
) ranked
WHERE salary_year_avg > title_avg
ORDER BY job_title_short, salary_year_avg DESC;
```

The window function version executes the aggregation once per partition, not once per row.

## Notes

- **Correlated vs. uncorrelated**: Always verify in the EXPLAIN plan whether your subquery is truly correlated (references outer table). If it isn't, move it outside to reduce redundant execution.
- **Rewrite to JOIN or window functions**: Whenever possible, replace correlated subqueries with `LEFT JOIN` + aggregation or `OVER()` clauses. These scale linearly; correlated subqueries often scale quadratically.
- **Caching limits**: Scalar subquery caching works best with simple deterministic expressions. Complex subqueries or those with function calls may not cache, even if technically deterministic.
- **NULL handling**: Correlated subqueries with NULL values in the predicate can produce unexpected results (three-valued logic). Always add `IS NOT NULL` guards in aggregates and join conditions.
- **Adjacent topics**: Query plan analysis (EXPLAIN ANALYZE), index usage on join/filter columns, materialized CTEs (WITH), and the difference between EXISTS vs. IN in subqueries (EXISTS short-circuits; IN does not).
