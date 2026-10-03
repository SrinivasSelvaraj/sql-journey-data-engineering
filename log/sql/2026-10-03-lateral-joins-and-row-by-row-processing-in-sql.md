---
date: 2026-10-03
phase: sql
topic: Lateral joins and row-by-row processing in SQL
---

# Lateral joins and row-by-row processing in SQL

*SQL for analytics and engineering*

## Concept

A lateral join (or cross apply in some SQL dialects) processes each row of a left table by executing a subquery that references that row's values. Unlike standard joins where the join condition is evaluated once, lateral joins re-execute the right-side logic for *each* left-side row, enabling row-by-row transformations, ranking within groups, and complex sequential logic. This is essential when you need to apply a different filter, aggregation, or window function *per row context* rather than globally.

Lateral joins matter most when standard window functions become awkward—for example, getting the top 3 most recent job postings per location, or finding the next event after a given timestamp for each row. Without lateral joins, you'd be forced into inefficient self-joins, CTEs with row numbering that bloat your logic, or application-layer processing. They also unlock row-by-row correlated subqueries in a way that's readable and performant if the optimizer is smart.

The key risk: lateral joins can become expensive if the inner query is non-trivial and the outer table is large, because you're repeating work for every outer row. If you don't have a reasonable filter or index on the inner table, this degrades quickly. Always reason about the cardinality and whether a window function or standard join could solve the problem more efficiently first.

## Practice

**Problem:** For each job location, find the 3 most recent job postings and their salary. Return location, job_id, job_title_short, salary_year_avg, and posted_date, ordered by location and recency.

```sql
SELECT
  jp.job_location,
  jp_recent.job_id,
  jp_recent.job_title_short,
  jp_recent.salary_year_avg,
  jp_recent.job_posted_date
FROM (
  SELECT DISTINCT job_location FROM job_postings_fact
) locations
LATERAL JOIN (
  SELECT job_id, job_title_short, salary_year_avg, job_posted_date
  FROM job_postings_fact jp
  WHERE jp.job_location = locations.job_location
  ORDER BY jp.job_posted_date DESC
  LIMIT 3
) jp_recent
ORDER BY locations.job_location, jp_recent.job_posted_date DESC;
```

*Note: Syntax varies by dialect (LATERAL in PostgreSQL, CROSS APPLY in SQL Server, LATERAL in BigQuery). If using a system without native lateral join support, rewrite using window functions:*

```sql
WITH ranked AS (
  SELECT
    job_location, job_id, job_title_short, salary_year_avg, job_posted_date,
    ROW_NUMBER() OVER (PARTITION BY job_location ORDER BY job_posted_date DESC) as rn
  FROM job_postings_fact
)
SELECT * FROM ranked WHERE rn <= 3
ORDER BY job_location, job_posted_date DESC;
```

## Notes

- **Window functions first:** Always check if `ROW_NUMBER()`, `RANK()`, or `DENSE_RANK()` can do the job—they're usually more efficient and portable than lateral joins.
- **Lateral vs. correlated subqueries:** A lateral join is a readable way to write what would otherwise be a messy correlated scalar subquery in the SELECT clause; both re-execute per row, but lateral is cleaner for multi-row results.
- **Index awareness:** Lateral joins shine when the inner query can use an index on the filtering column (e.g., `job_location`). Without it, you're doing a table scan per outer row.
- **Dialect differences:** PostgreSQL, BigQuery, and Snowflake all support `LATERAL`; SQL Server uses `CROSS APPLY` and `OUTER APPLY`. MySQL and SQLite have limited or no native support—reach for window functions instead.
- **Optimization**: If the outer table is small and the inner table is large with good indexes, lateral joins can be very fast. If reversed, they become a bottleneck; consider materializing the inner result first.
