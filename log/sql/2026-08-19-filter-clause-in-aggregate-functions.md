---
date: 2026-08-19
phase: sql
topic: FILTER clause in aggregate functions
---

# FILTER clause in aggregate functions

*SQL for analytics and engineering*

## Concept

The `FILTER` clause allows you to apply a `WHERE`-like condition directly within an aggregate function, computing the aggregate over only rows that match the condition. It sits between the function and the `OVER` clause (if present) and is cleaner and more efficient than wrapping aggregates in `CASE` statements.

Without `FILTER`, you must use `SUM(CASE WHEN condition THEN value ELSE 0 END)` or similar workarounds, which are verbose and can confuse query optimizers. `FILTER` makes intent explicit: you're aggregating a *subset* of rows, not the entire group. This matters for correctness in multi-condition aggregations and for readability in analytical queries where you need side-by-side comparisons of different subsets.

The syntax is simple: `AGG_FUNCTION(column) FILTER (WHERE condition)`. It works with any aggregate (`COUNT`, `SUM`, `AVG`, `MAX`, `MIN`) and is standard in PostgreSQL, supported in most modern databases (though not all—notably older MySQL versions).

## Practice

**Problem:** For each job title, calculate the total salary budget and the count of remote positions, separately. Compare how many positions are remote vs. non-remote by title.

```sql
SELECT
  job_title_short,
  COUNT(*) FILTER (WHERE job_work_from_home = true) AS remote_count,
  COUNT(*) FILTER (WHERE job_work_from_home = false) AS onsite_count,
  SUM(salary_year_avg) FILTER (WHERE job_work_from_home = true) AS remote_salary_total,
  SUM(salary_year_avg) FILTER (WHERE job_work_from_home = false) AS onsite_salary_total
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY job_title_short
ORDER BY remote_count DESC;
```

## Notes

- **CASE vs. FILTER:** `FILTER` is functionally identical to `CASE` but reads left-to-right and signals intent better; prefer `FILTER` in all modern SQL contexts for clarity and potential optimizer wins.
- **NULL handling:** `FILTER` excludes rows where the condition is NULL or FALSE, just like `WHERE`; use explicit `IS NOT NULL` if filtering on a nullable column.
- **Window functions:** `FILTER` also works with window functions (e.g., `ROW_NUMBER() FILTER (WHERE ...)`), enabling conditional ranking and running totals without subqueries.
- **Aggregate correctness:** When comparing multiple filtered aggregates in the same query, `FILTER` prevents you from accidentally conflating row counts; each aggregate counts independently.
- **Performance:** Query planners in PostgreSQL and modern databases often optimize `FILTER` better than `CASE` because the condition is structurally separated; test with `EXPLAIN` if performance matters.
