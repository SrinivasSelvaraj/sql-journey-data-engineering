---
date: 2026-10-22
phase: sql
topic: Materialized views vs dynamic views for performance
---

# Materialized views vs dynamic views for performance

*SQL for analytics and engineering*

## Concept

A **materialized view** is a query result stored physically on disk and refreshed on a schedule, while a **dynamic view** executes its underlying query every time it's referenced. Materialized views trade storage and staleness for speed: aggregations, joins, and transformations happen once, not repeatedly. Dynamic views are always current but recompute expensive logic on every access.

For analytics, materialized views shine when the same aggregation (e.g., daily job posting counts by title) is queried thousands of times but only needs hourly or daily freshness. Without them, each query scans raw tables, multiplying I/O and CPU costs. Dynamic views work well for lightweight transformations, frequently changing dimensions, or when freshness is critical enough to justify the compute cost.

The performance difference becomes severe at scale: a dynamic view joining job_postings_fact to itself for YoY salary comparison might take 30 seconds; the same query on a materialized view takes <100ms. Cost and latency are two sides of the same coin—choose materialized views when you tolerate slight staleness for dramatic speed gains.

## Practice

**Problem:** Your analytics team queries job posting volume and average salary by job_title_short every 15 minutes for dashboards. The query joins job_postings_fact to itself to compare current month vs. last month. Raw tables have millions of rows. Design a solution.

```sql
-- Create materialized view (refreshed hourly)
CREATE MATERIALIZED VIEW mv_job_title_metrics AS
SELECT
  job_title_short,
  DATE_TRUNC('month', job_posted_date) AS metric_month,
  COUNT(*) AS posting_count,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary,
  COUNT(CASE WHEN job_work_from_home THEN 1 END) AS remote_count
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY job_title_short, DATE_TRUNC('month', job_posted_date);

CREATE INDEX idx_mv_title_month ON mv_job_title_metrics(job_title_short, metric_month);

-- Fast dashboard query (executes in <100ms)
SELECT
  curr.job_title_short,
  curr.posting_count AS current_month_postings,
  prev.posting_count AS prev_month_postings,
  ROUND(
    ((curr.posting_count - prev.posting_count)::NUMERIC / prev.posting_count * 100),
    2
  ) AS pct_change,
  curr.avg_salary,
  prev.avg_salary
FROM mv_job_title_metrics curr
LEFT JOIN mv_job_title_metrics prev
  ON curr.job_title_short = prev.job_title_short
  AND prev.metric_month = DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')
WHERE curr.metric_month = DATE_TRUNC('month', CURRENT_DATE)
ORDER BY pct_change DESC;

-- Refresh strategy (e.g., hourly via cron or trigger)
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_job_title_metrics;
```

## Notes

- **Staleness lag:** Materialized views introduce a freshness window (refresh interval). If dashboards must reflect posts from 30 seconds ago, this fails; use dynamic views instead.
- **Index strategy:** Materialized views benefit from indexes on common filter/join columns (job_title_short, metric_month above). Dynamic views inherit table indexes but don't store redundant copies.
- **Refresh locking:** `REFRESH MATERIALIZED VIEW` locks reads in most databases; use `CONCURRENT` mode (Postgres) or schedule refreshes during low-traffic windows.
- **Query plan inspection:** Always `EXPLAIN` the materialized view query before and after materialization. If the MV query itself is inefficient (bad GROUP BY order, missing WHERE), it won't help—fix the underlying logic first.
- **Adjacent concepts:** Incremental refresh (append-only new rows instead of full recalculation), columnar storage (Parquet, ORC optimize analytical MVs), and partitioning (refresh only today's partition) all extend this pattern.
