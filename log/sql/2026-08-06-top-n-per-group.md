---
date: 2026-08-06
phase: sql
topic: Top N per group
---

# Top N per group

*SQL for analytics and engineering*

## Concept

Top N per group is a fundamental analytics pattern where you rank rows within each group and filter for only the top ranks. This appears constantly in real work: finding the highest-paying job in each location, the most recent order per customer, or the three fastest-growing products per category. Without this pattern, you either pull all data and filter in application code (wasteful) or write incomplete queries that miss edge cases.

The core challenge is that `WHERE` clauses cannot reference window functions directly—you must use a subquery or CTE to compute ranks first, then filter in the outer query. Many candidates attempt `GROUP BY` with `MAX()` or `MIN()`, which fails when you need the full row (not just the aggregated value) or when there are ties. The window function `ROW_NUMBER()`, `RANK()`, or `DENSE_RANK()` paired with `PARTITION BY` solves this elegantly.

This skill matters because it reflects understanding of execution order (logical vs. physical), the difference between aggregate and window functions, and how to write queries that databases can optimize efficiently. On interviews, it's also a checkpoint for whether you've done real SQL work.

## Practice

**Problem:** Find the top 2 highest-paying job postings (by salary_year_avg) for each job_location. If a location has fewer than 2 postings, include all of them. Return job_id, job_title_short, job_location, and salary_year_avg.

```sql
WITH ranked_jobs AS (
  SELECT
    job_id,
    job_title_short,
    job_location,
    salary_year_avg,
    ROW_NUMBER() OVER (PARTITION BY job_location ORDER BY salary_year_avg DESC) AS salary_rank
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
)
SELECT
  job_id,
  job_title_short,
  job_location,
  salary_year_avg
FROM ranked_jobs
WHERE salary_rank <= 2
ORDER BY job_location, salary_rank;
```

## Notes

- **ROW_NUMBER vs. RANK vs. DENSE_RANK**: Use `ROW_NUMBER()` when ties should receive different ranks (1, 2, 3, 4). Use `RANK()` when ties get the same rank but skip numbers (1, 2, 2, 4). Use `DENSE_RANK()` for ties with no gaps (1, 2, 2, 3). For "top N," `ROW_NUMBER()` is safest unless you specifically want all tied rows.

- **Subquery materialization**: The CTE makes the query readable, but some databases (especially older versions) may materialize it unnecessarily. If performance is critical, verify the execution plan; consider moving the window function into the WHERE clause using a derived table instead.

- **NULL handling**: Always check for NULL in the ordering column. A NULL salary can unexpectedly rank first or last depending on the database's `NULLS FIRST/LAST` behavior. Filter or specify behavior explicitly.

- **Ties at the boundary**: If you use `RANK()` and there's a tie at rank 2, you might get 3 or 4 rows per group. Clarify the requirement (hard N vs. "all ties at the boundary") before writing.

- **Related patterns**: Master this alongside cumulative sums (`SUM() OVER ORDER BY`), running averages, and lag/lead functions. Also revisit how indexes on partition and order columns affect query plans—a good index can make window functions much faster.
