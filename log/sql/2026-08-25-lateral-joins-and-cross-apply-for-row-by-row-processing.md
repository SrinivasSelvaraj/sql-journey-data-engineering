---
date: 2026-08-25
phase: sql
topic: Lateral joins and cross apply for row-by-row processing
---

# Lateral joins and cross apply for row-by-row processing

*SQL for analytics and engineering*

## Concept

A lateral join (or CROSS APPLY in SQL Server) allows each row from the left table to execute a subquery on the right, where that subquery can reference columns from the left row. This is row-by-row processing at the SQL level—unlike a regular JOIN that evaluates the join condition once, a lateral join re-evaluates the right side for *every* row on the left. The key difference from a standard join: the right-hand query is correlated and **dependent on each left row**.

When does this matter? When you need to:
- Fetch the top N related rows per group (e.g., top 3 salaries per job title)
- Perform calculations that depend on ordering within each group (e.g., salary percentile relative to peers)
- Unnest or explode data conditionally based on left-row context

Without lateral joins, you'd resort to window functions (which are usually better), self-joins with ranking subqueries (verbose), or application-layer processing (slow, error-prone).

In PostgreSQL, use LATERAL; in SQL Server, use CROSS APPLY; in Snowflake/BigQuery, use lateral joins or FLATTEN. The performance cost is real—each left row triggers a subquery execution—so use sparingly and ensure the right side is indexed or fast.

## Practice

**Problem:** For each job title, find the top 2 highest-paying job postings (by salary_year_avg). Return job_title_short, job_id, and salary_year_avg.

```sql
SELECT 
  jp.job_title_short,
  lateral_jobs.job_id,
  lateral_jobs.salary_year_avg
FROM (
  SELECT DISTINCT job_title_short 
  FROM job_postings_fact
) jp
CROSS APPLY (
  SELECT TOP 2
    job_id,
    salary_year_avg
  FROM job_postings_fact
  WHERE job_title_short = jp.job_title_short
    AND salary_year_avg IS NOT NULL
  ORDER BY salary_year_avg DESC
) lateral_jobs
ORDER BY jp.job_title_short, lateral_jobs.salary_year_avg DESC;
```

*PostgreSQL equivalent:*
```sql
SELECT 
  jp.job_title_short,
  lateral_jobs.job_id,
  lateral_jobs.salary_year_avg
FROM (
  SELECT DISTINCT job_title_short 
  FROM job_postings_fact
) jp
CROSS JOIN LATERAL (
  SELECT 
    job_id,
    salary_year_avg
  FROM job_postings_fact
  WHERE job_title_short = jp.job_title_short
    AND salary_year_avg IS NOT NULL
  ORDER BY salary_year_avg DESC
  LIMIT 2
) lateral_jobs
ORDER BY jp.job_title_short, lateral_jobs.salary_year_avg DESC;
```

## Notes

- **Mistake:** Forgetting that the right-side subquery runs *per left row*—this kills performance on large datasets. Always check the query plan for nested loop joins; consider window functions (ROW_NUMBER() OVER PARTITION BY) as a faster alternative when applicable.

- **Window functions vs. lateral:** For top-N-per-group, `ROW_NUMBER() OVER (PARTITION BY job_title_short ORDER BY salary_year_avg DESC)` is nearly always faster than a lateral join because it scans once, not row-by-row. Use lateral joins only when window functions can't express the logic.

- **Indexing matters:** If your lateral subquery filters heavily (e.g., WHERE job_title_short = jp.job_title_short), an index on job_title_short will make a massive difference. Without it, each row triggers a full table scan.

- **CROSS APPLY vs. OUTER APPLY:** CROSS APPLY (inner join semantics) drops left rows with no matches; OUTER APPLY (left join semantics) keeps them. Choose based on whether you want nulls in output.

- **Adjacent topics:** Revisit window functions, query execution plans (nested loop detection), and correlated subqueries. Lateral joins are the "structured" way to do what correlated subqueries do informally—understand both for interview discussion.
