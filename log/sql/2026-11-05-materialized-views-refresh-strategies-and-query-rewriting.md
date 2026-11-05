---
date: 2026-11-05
phase: sql
topic: Materialized views: refresh strategies and query rewriting
---

# Materialized views: refresh strategies and query rewriting

*SQL for analytics and engineering*

## Concept

A materialized view is a database object that physically stores the result set of a query, unlike a regular view which is recomputed on every access. This matters because analytical queries often join large fact and dimension tables repeatedly—materializing expensive aggregations or denormalizations trades storage cost for dramatic query speedup. Without refresh strategies, materialized views become stale; without query rewriting, the optimizer may not recognize opportunities to use them, defeating the purpose.

Refresh strategies fall into two buckets: **full refresh** (drop and rebuild the entire view) and **incremental refresh** (update only changed rows since last refresh). Full refresh is simpler but expensive for large views; incremental requires tracking which source rows changed, using approaches like CDC (change data capture) or timestamp columns. Query rewriting—either manual or automatic via the optimizer—redirects queries that could use a materialized view to actually hit it instead of recomputing from base tables.

In practice, you'll design materialized views for high-cardinality aggregations (e.g., salary statistics by job title and location), denormalized reporting layers, or expensive transformations (e.g., filtering outliers). The cost-benefit hinges on refresh frequency, query volume, and staleness tolerance: a dashboard refreshed hourly with 100 queries per minute justifies a materialized view; a one-off analysis does not.

## Practice

**Problem:** You need to support interactive queries on average salaries by job_title_short and job_location, with results needed within sub-second latency. Raw job_postings_fact has 500k rows. Design a materialized view and an incremental refresh strategy using a last_refreshed timestamp.

```sql
-- Create the materialized view
CREATE MATERIALIZED VIEW mv_salary_by_title_location AS
SELECT 
  job_title_short,
  job_location,
  COUNT(*) as job_count,
  ROUND(AVG(salary_year_avg), 2) as avg_salary,
  MIN(salary_year_avg) as min_salary,
  MAX(salary_year_avg) as max_salary,
  MAX(job_posted_date) as latest_job_date
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY job_title_short, job_location;

-- Initial full refresh
REFRESH MATERIALIZED VIEW mv_salary_by_title_location;

-- Incremental refresh (assumes job_postings_fact has a last_modified column)
-- Run this hourly or on a schedule
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_salary_by_title_location;

-- Query the materialized view (optimizer will use it directly)
SELECT 
  job_title_short,
  job_location,
  avg_salary,
  job_count
FROM mv_salary_by_title_location
WHERE job_title_short = 'Data Engineer'
ORDER BY avg_salary DESC;
```

For true incremental refresh in PostgreSQL or similar systems without built-in change tracking, maintain a refresh metadata table and merge only rows where job_posted_date > last_refresh_time.

## Notes

- **Staleness vs. freshness trade-off:** Every refresh consumes I/O and compute; decide tolerable lag based on use case (real-time dashboards need frequent refresh; monthly reports can afford overnight).
- **Query rewriting blindness:** Some ORMs and query builders won't recognize when a materialized view answers their query; you may need manual UNION ALL logic or hints to force use.
- **Incremental refresh complexity:** CDC-based approaches (Postgres LISTEN/NOTIFY, MySQL binlog, Kafka) are powerful but introduce operational overhead; simpler timestamp-based strategies work well for append-heavy fact tables.
- **Indexing the materialized view:** A materialized view is just a table—index it on frequently filtered or joined columns (job_title_short, job_location) to maximize benefit.
- **Related to:** query plan analysis, denormalization patterns, OLAP vs. OLTP, partitioning strategies for large aggregations.
