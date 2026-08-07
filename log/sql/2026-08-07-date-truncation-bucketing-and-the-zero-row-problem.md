---
date: 2026-08-07
phase: sql
topic: Date truncation, bucketing and the zero-row problem
---

# Date truncation, bucketing and the zero-row problem

*SQL for analytics and engineering*

## Concept

Date truncation converts timestamps or dates to a common granularity (year, month, day) to enable accurate grouping and aggregation. Without truncation, a `GROUP BY` on raw timestamps treats `2024-01-15 09:30:00` and `2024-01-15 14:22:00` as separate groups—defeating the analysis. Bucketing extends this: you bin continuous values (salary, tenure, response time) into discrete ranges to reveal distribution patterns and reduce cardinality.

The zero-row problem emerges when you group and filter aggressively. If you `GROUP BY date_trunc(job_posted_date, 'month')` then `HAVING COUNT(*) > 100`, you silently drop months with fewer postings—biasing your trend analysis. Similarly, if you bucket salary into $10k ranges but filter `WHERE salary_year_avg > 200000`, you lose the context of lower-paying jobs entirely, making your bucketed distribution misleading or incomplete.

These patterns matter because they directly affect dashboard correctness and interview performance: careless truncation causes off-by-one errors, suspicious zero-row gaps in time series look like bugs, and bucketing without understanding your filter scope leads to false conclusions about data shape.

## Practice

**Problem:** Your analytics team wants a monthly report of average salary by job location, but only for remote positions posted in 2024. They also want to see *all months* in 2024, even if no remote jobs were posted that month in certain locations—otherwise the dashboard will have confusing gaps.

```sql
-- Generate all month-location combinations for 2024
WITH date_spine AS (
  SELECT DATE_TRUNC(d, 'month') AS month_bucket
  FROM GENERATE_DATE_ARRAY('2024-01-01', '2024-12-31', INTERVAL 1 DAY) AS d
  GROUP BY month_bucket
),
locations AS (
  SELECT DISTINCT job_location
  FROM job_postings_fact
  WHERE DATE_TRUNC(job_posted_date, 'month') >= '2024-01-01'
    AND job_work_from_home = TRUE
),
spine AS (
  SELECT ds.month_bucket, l.job_location
  FROM date_spine ds
  CROSS JOIN locations l
),
monthly_data AS (
  SELECT 
    DATE_TRUNC(jp.job_posted_date, 'month') AS month_bucket,
    jp.job_location,
    AVG(jp.salary_year_avg) AS avg_salary,
    COUNT(*) AS job_count
  FROM job_postings_fact jp
  WHERE DATE_TRUNC(jp.job_posted_date, 'month') >= '2024-01-01'
    AND jp.job_work_from_home = TRUE
    AND jp.salary_year_avg IS NOT NULL
  GROUP BY 1, 2
)
SELECT 
  s.month_bucket,
  s.job_location,
  COALESCE(md.avg_salary, 0) AS avg_salary,
  COALESCE(md.job_count, 0) AS job_count
FROM spine s
LEFT JOIN monthly_data md
  ON s.month_bucket = md.month_bucket
  AND s.job_location = md.job_location
ORDER BY s.month_bucket, s.job_location;
```

## Notes

- **Truncation order matters:** Always truncate *before* filtering on date ranges; truncating after filtering can produce incomplete buckets (e.g., Feb 1–28 when you truncate Feb 15 data).
- **Zero-row trap:** `HAVING COUNT(*) > 0` hides zero-row groups. Use a spine/calendar table or `FULL OUTER JOIN` to preserve missing combinations—critical for time-series dashboards.
- **Salary bucketing adjacent:** When you bin continuous values, document your bucket edges (e.g., `[0, 50k), [50k, 100k), [100k+)`) and test boundary rows; off-by-one mistakes are common and hard to spot in production.
- **Revisit: LEFT JOIN logic** when combining spines with fact tables—mixing INNER JOIN accidentally re-introduces the zero-row problem.
- **Performance note:** Spines on large date ranges or high cardinality dimensions can balloon result size before the join; use `LIMIT` in CTEs during development to catch runaway queries early.
