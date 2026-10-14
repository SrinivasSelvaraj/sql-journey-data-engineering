---
date: 2026-10-14
phase: cloud
topic: BigQuery materialized views: auto-refresh and staleness
---

# BigQuery materialized views: auto-refresh and staleness

*Cloud platforms and storage*

## Concept

A BigQuery materialized view is a precomputed table that stores query results and can automatically refresh on a schedule. Unlike a logical view (which executes the query every time you reference it), a materialized view executes once, writes the result to storage, and reuses that cached result until the next refresh. This matters when you have expensive aggregations or joins that many queries depend on—you pay for one computation instead of many.

The key tension is freshness vs. cost. Auto-refresh runs on a schedule (hourly, daily, etc.), so your downstream queries see stale data. If source tables change between refreshes, users get old results. Without understanding this trade-off, you'll either overpay (refreshing too often) or surface incorrect analysis (refreshing too rarely).

What breaks: if your dashboard or report doesn't document the refresh cadence, stakeholders assume data is current. If you query a materialized view at 14:59 and the daily refresh happens at 15:00, you're seeing yesterday's picture. On the flip side, refreshing every 5 minutes for a view that doesn't need it wastes slot time and increases your GCP bill.

## Practice

**Problem:** Your analytics team runs frequent queries on job postings, filtering by location and aggregating median salary by job title. The base `job_postings_fact` table receives new postings hourly, but analysts only need salary trends updated daily at 8 AM.

```sql
CREATE MATERIALIZED VIEW job_salary_summary AS
SELECT
  job_title_short,
  job_location,
  COUNT(*) AS posting_count,
  APPROX_QUANTILES(salary_year_avg, 100)[OFFSET(50)] AS median_salary,
  MAX(job_posted_date) AS latest_posting_date
FROM
  `project.dataset.job_postings_fact`
WHERE
  job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
GROUP BY
  job_title_short,
  job_location;

-- Schedule auto-refresh daily at 08:00 UTC
ALTER MATERIALIZED VIEW job_salary_summary
SET OPTIONS (
  enable_refresh = true,
  refresh_interval_minutes = 1440  -- 24 hours
);
```

Downstream queries now hit the materialized view (cheap) instead of rescanning `job_postings_fact` 50 times per day (expensive).

## Notes

- **Refresh costs money**: every auto-refresh is a full query execution against source tables. A daily refresh of a 100 GB scan costs the same as one analyst running that query once—but if 20 people would have run it, you save 19 scans.
- **Staleness is silent**: add a `latest_posting_date` or metadata column to materialized views so consumers know the cutoff; document refresh SLA in comments or a data catalog.
- **Not a substitute for caching**: materialized views are for expensive recurring queries; for one-off exploratory work, use `CACHE` or `results_cache_enabled=true` instead.
- **Incremental refresh gotcha**: BigQuery materialized views do *not* support incremental refresh (only full refresh). If your base table has billions of rows, daily full refreshes can get expensive; consider partitioning and clustering the source table, or using a scheduled query + destination table pattern instead.
- **Adjacent topics**: scheduled queries (simpler, no auto-refresh), query slots (how auto-refresh contends with interactive queries), change data capture (CDC) patterns for near-real-time materialization.
