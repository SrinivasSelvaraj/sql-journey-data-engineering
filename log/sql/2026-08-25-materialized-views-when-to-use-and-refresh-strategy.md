---
date: 2026-08-25
phase: sql
topic: Materialized views: when to use and refresh strategy
---

# Materialized views: when to use and refresh strategy

*SQL for analytics and engineering*

## Concept

A materialized view is a database object that stores the result set of a query physically on disk, unlike a standard view which re-executes the query each time it's called. This matters when you have expensive aggregations, joins across large tables, or analytics queries that run frequently—materializing pre-computes the work once and lets subsequent queries scan a much smaller result set. Without materialized views, you either accept slow query times (re-running expensive logic) or duplicate code (writing the same complex query in multiple places).

The trade-off is freshness vs. performance. A materialized view becomes stale immediately after the source data changes, so you must define a refresh strategy: full refresh (recompute everything), incremental refresh (only update changed rows), or event-driven refresh (trigger on INSERT/UPDATE). Choose based on your data volatility, acceptable staleness SLA, and available compute budget. For a hiring analytics dashboard querying job postings updated daily, a nightly full refresh usually works; for real-time fraud detection, materialized views are the wrong tool.

## Practice

**Problem:** You need to serve a dashboard that shows average salary by job title and work-from-home status. This query runs 50+ times per day across thousands of job postings. Write a materialized view and a refresh strategy.

```sql
-- Create the materialized view
CREATE MATERIALIZED VIEW mv_salary_by_title_wfh AS
SELECT 
  job_title_short,
  job_work_from_home,
  COUNT(*) as posting_count,
  ROUND(AVG(salary_year_avg), 2) as avg_salary,
  ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg), 2) as median_salary,
  MAX(job_posted_date) as latest_posting_date
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY job_title_short, job_work_from_home;

-- Create index on common filter columns for dashboard queries
CREATE INDEX idx_mv_title_wfh ON mv_salary_by_title_wfh(job_title_short, job_work_from_home);

-- Refresh strategy: full refresh nightly (assumes batch job postings load)
-- Run this as a scheduled job (e.g., via cron or cloud scheduler) at 2 AM
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_salary_by_title_wfh;

-- Query the materialized view (instant response, no re-aggregation)
SELECT * FROM mv_salary_by_title_wfh
WHERE job_title_short = 'Data Engineer' AND job_work_from_home = TRUE;
```

## Notes

- **Staleness is real**: Materialized views don't auto-refresh in most databases (Postgres `REFRESH`, BigQuery automatic refresh settings vary). Always document the refresh cadence so stakeholders know the data lag.
- **Incremental refresh is hard**: If you need sub-hourly freshness, investigate change data capture (CDC) or event streaming instead; full rebuilds on large views become expensive.
- **Index the materialized view**: Treat it like a table—add indexes on columns commonly used in WHERE clauses, otherwise you've just moved the query bottleneck.
- **Watch out for NULL handling**: Aggregates skip NULLs, but GROUP BY includes NULL as a distinct group. Explicitly filter (as shown) to avoid surprise rows.
- **Related concepts**: Query result caching (Redis, Memcached) for ephemeral hot data; fact tables and star schema design for pre-normalized analytics; incremental materialization via merge-on-read or insert-only patterns in data warehouses (Snowflake, BigQuery).
