---
date: 2026-08-07
phase: sql
topic: Unpivoting wide tables to long format
---

# Unpivoting wide tables to long format

*SQL for analytics and engineering*

## Concept

Unpivoting transforms wide tables—where multiple related columns represent a single dimension—into long format, where each row represents one observation. This is essential for analytics because most visualization tools, statistical functions, and time-series operations assume long format. Wide tables are efficient for OLTP systems but create redundancy and make aggregations painful: if you have `q1_revenue, q2_revenue, q3_revenue, q4_revenue` as columns, computing year-over-year comparisons requires self-joins or complex CASE logic.

The unpivoting pattern uses `UNION ALL` to stack column values into rows, creating a tidy dataset where attributes belong in columns and measurements belong in rows. Without it, you either write brittle queries that hardcode column names, or you miss analytical opportunities entirely. Most SQL engines support `UNPIVOT` syntax (Postgres uses `CROSS JOIN UNNEST`, BigQuery uses `CROSS JOIN UNNEST`, SQL Server has native `UNPIVOT`), but `UNION ALL` is universally portable.

## Practice

**Problem:** You have a job postings table where salary data is split across three seniority levels: `entry_level_salary, mid_level_salary, senior_level_salary`. You need to unpivot this into a long format with columns `seniority_level` and `salary` for downstream analytics and visualization.

```sql
SELECT 
  job_id,
  job_title_short,
  job_posted_date,
  job_location,
  'entry_level' AS seniority_level,
  entry_level_salary AS salary
FROM job_postings_fact
WHERE entry_level_salary IS NOT NULL

UNION ALL

SELECT 
  job_id,
  job_title_short,
  job_posted_date,
  job_location,
  'mid_level' AS seniority_level,
  mid_level_salary AS salary
FROM job_postings_fact
WHERE mid_level_salary IS NOT NULL

UNION ALL

SELECT 
  job_id,
  job_title_short,
  job_posted_date,
  job_location,
  'senior_level' AS seniority_level,
  senior_level_salary AS salary
FROM job_postings_fact
WHERE senior_level_salary IS NOT NULL
```

## Notes

- **NULL handling:** Filter NULL values in each UNION branch to avoid polluting results; alternatively, use `COALESCE` in a WHERE clause to keep only rows where *any* salary exists, then unpivot selectively.
- **UNION vs UNION ALL:** Always use `UNION ALL` for unpivoting—`UNION` deduplicates, adding unnecessary overhead; since you're creating distinct rows per seniority level, duplicates are impossible and unwanted.
- **Scale concern:** Unpivoting triples (or N-multiplies) row count; on large tables this can hit memory limits. Consider materializing as a temp table or CTE in production rather than nesting within a larger query.
- **Adjacent topic:** Pivoting (the reverse operation) uses `GROUP BY` + `MAX(CASE WHEN...)` or native `PIVOT` syntax; mastering both directions makes you fluent in reshaping data for different consumers.
- **Revisit:** When unpivoting many columns (10+), template generation via Python or jinja becomes practical; also review your engine's native `UNPIVOT` or `CROSS JOIN UNNEST` syntax for readability gains on smaller datasets.
