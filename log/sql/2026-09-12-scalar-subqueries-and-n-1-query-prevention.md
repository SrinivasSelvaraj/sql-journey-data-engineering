---
date: 2026-09-12
phase: sql
topic: Scalar subqueries and N+1 query prevention
---

# Scalar subqueries and N+1 query prevention

*SQL for analytics and engineering*

## Concept

A **scalar subquery** returns exactly one row and one column, allowing you to embed computed values directly into SELECT, WHERE, or JOIN clauses. Without scalar subqueries, you often resort to self-joins or window functions—both of which can be inefficient or harder to reason about. The **N+1 problem** occurs when your application executes one query to fetch a parent row, then runs N additional queries in a loop to fetch related child data. In SQL, this manifests as redundant filtering or aggregation logic repeated across multiple statements instead of being computed once and reused.

Scalar subqueries prevent N+1 by computing derived values (like "max salary for this job title" or "count of posts by this company") *within a single query execution*, eliminating the need for multiple round-trips. The database query planner can optimize correlated and non-correlated subqueries differently, so understanding *when* a subquery depends on outer rows is critical for performance. Without this technique, you either fetch excessive data and filter in application code, or you write multiple queries—both destroy performance under scale.

## Practice

**Problem:** Find the job title, salary, and the difference between that job's salary and the maximum salary offered for *any* job in the same location. Identify which jobs pay below the location's peak.

```sql
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_location,
  salary_year_avg - (
    SELECT MAX(salary_year_avg)
    FROM job_postings_fact jf2
    WHERE jf2.job_location = jf1.job_location
      AND jf2.salary_year_avg IS NOT NULL
  ) AS salary_gap_from_max
FROM job_postings_fact jf1
WHERE salary_year_avg IS NOT NULL
  AND salary_year_avg < (
    SELECT MAX(salary_year_avg)
    FROM job_postings_fact jf2
    WHERE jf2.job_location = jf1.job_location
      AND jf2.salary_year_avg IS NOT NULL
  )
ORDER BY job_location, salary_gap_from_max DESC;
```

**Why this works:** The correlated subqueries (jf2.job_location = jf1.job_location) are evaluated once *per outer row*, not once per application iteration. The database planner can decide whether to materialize the subquery or execute it inline. Without scalar subqueries, you'd either fetch all jobs and filter in Python, or run one query per location—the classic N+1.

## Notes

- **Correlated vs. non-correlated:** A correlated subquery references outer row values (slower, one per outer row); a non-correlated one doesn't (can be run once and reused). Always check the WHERE clause to see what's being joined.
- **Scalar subquery must return exactly one row.** If it returns zero or multiple rows, you get an error. Use aggregates (MAX, MIN, COUNT) or LIMIT 1 + ORDER BY to guarantee cardinality.
- **Window functions often replace scalar subqueries.** `ROW_NUMBER() OVER (PARTITION BY job_location ORDER BY salary_year_avg DESC)` can be cleaner and faster than a correlated subquery, especially in modern OLAP engines.
- **Common mistake:** Forgetting to handle NULL values in subqueries. `MAX(salary_year_avg)` on a nullable column can return NULL, causing outer rows to also become NULL—use IS NOT NULL in both the subquery and outer filter.
- **Adjacent topics:** EXPLAIN / query plans (to verify subquery is not causing a Cartesian product), derived tables (FROM clause subqueries, useful for pre-filtering before the main query), and CTE materialization hints (WITH ... AS).
