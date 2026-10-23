---
date: 2026-10-23
phase: sql
topic: Lateral joins and correlated subquery execution
---

# Lateral joins and correlated subquery execution

*SQL for analytics and engineering*

## Concept

A **lateral join** (or cross apply in some databases) allows each row from the left table to independently execute a subquery on the right side, with the subquery able to reference columns from the current left row. This differs from a standard join where the join condition is evaluated once; in a lateral join, the right-hand operation runs *per row*. Without lateral joins, you'd need window functions, CTEs with ranking, or self-joins to solve correlated problems—often less efficiently.

**Correlated subqueries** achieve similar goals but are frequently slower because the database must re-evaluate the subquery for each outer row without optimization opportunities. Lateral joins make the correlation explicit to the query planner, enabling better execution strategies. They matter most when you need the *top N results per group*, *ranked subsets*, or *running calculations* that depend on outer row values.

Without these tools, you either over-fetch data (join everything, then filter in application code) or write inefficient nested loops. Recognizing when a problem calls for lateral joins prevents O(n²) execution plans and unnecessary intermediate result sets.

## Practice

**Problem:** Find the 3 most recently posted jobs for each job title, showing job_id, job_title_short, job_posted_date, and salary_year_avg.

```sql
SELECT 
  jp.job_id,
  jp.job_title_short,
  jp.job_posted_date,
  jp.salary_year_avg
FROM job_postings_fact jp
CROSS JOIN LATERAL (
  SELECT 1
  FROM job_postings_fact jp2
  WHERE jp2.job_title_short = jp.job_title_short
    AND jp2.job_posted_date <= jp.job_posted_date
  ORDER BY jp2.job_posted_date DESC
  LIMIT 3
) AS recent_jobs
WHERE jp.job_posted_date IN (
  SELECT jp3.job_posted_date
  FROM job_postings_fact jp3
  WHERE jp3.job_title_short = jp.job_title_short
  ORDER BY jp3.job_posted_date DESC
  LIMIT 3
)
ORDER BY jp.job_title_short, jp.job_posted_date DESC;
```

*(Better alternative using window functions for clarity in most databases:)*

```sql
WITH ranked_jobs AS (
  SELECT 
    job_id,
    job_title_short,
    job_posted_date,
    salary_year_avg,
    ROW_NUMBER() OVER (PARTITION BY job_title_short ORDER BY job_posted_date DESC) AS rn
  FROM job_postings_fact
)
SELECT job_id, job_title_short, job_posted_date, salary_year_avg
FROM ranked_jobs
WHERE rn <= 3
ORDER BY job_title_short, job_posted_date DESC;
```

## Notes

- **Not all SQL engines support lateral joins equally.** PostgreSQL and some cloud warehouses (Snowflake, BigQuery with LATERAL) support them directly; MySQL and older SQL Server versions require workarounds like window functions or derived tables.

- **Window functions often replace lateral joins.** ROW_NUMBER(), RANK(), DENSE_RANK() with PARTITION BY solve most "top N per group" problems more cleanly and with better optimizer support.

- **Correlated subqueries in WHERE clauses are a red flag for performance.** Always check execution plans; a lateral join or CTE with window functions will typically outperform row-by-row subquery evaluation.

- **Lateral joins shine for non-aggregating subsets.** When you need filtered rows (not just aggregates) that depend on outer context—e.g., "the most expensive job posting for each location" with all its columns—lateral joins avoid redundant joins and aggregations.

- **Adjacent topics:** understand join order optimization, cardinality estimation (how many rows the subquery returns affects plan cost), and EXPLAIN/ANALYZE output to spot N+1 query patterns.
