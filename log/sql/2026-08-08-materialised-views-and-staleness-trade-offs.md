---
date: 2026-08-08
phase: sql
topic: Materialised views and staleness trade-offs
---

# Materialised views and staleness trade-offs

*SQL for analytics and engineering*

## Concept

A materialised view is a query result **physically stored as a table** on disk, not recomputed on every access like a virtual view. This trades storage and maintenance cost for query speed: analytics queries hit pre-aggregated data instead of rescanning millions of raw rows. The critical trade-off is **staleness**—how far behind the source data the view lags. In near-real-time systems, a materialised view that refreshes hourly may be stale by 59 minutes; in batch analytics refreshing nightly, staleness is acceptable. Without materialised views, expensive aggregations (sums over millions of rows, complex joins) run repeatedly; with them, you pay once during refresh, but queries answering "how many jobs posted today?" may return yesterday's count if the view hasn't refreshed yet. The decision hinges on: frequency of updates to source data, acceptable staleness window for business logic, and storage budget.

## Practice

**Problem:** Your analytics team queries job posting trends hourly. The raw `job_postings_fact` table has 5M rows and grows daily. They repeatedly run this query to populate dashboards:

```sql
SELECT 
  DATE(job_posted_date) AS posted_date,
  job_work_from_home,
  COUNT(*) AS posting_count,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY DATE(job_posted_date), job_work_from_home;
```

This scan takes 8 seconds. Create a materialised view that refreshes hourly, and rewrite the dashboard query.

```sql
-- Create materialised view (refreshes every hour via scheduler)
CREATE MATERIALIZED VIEW job_postings_daily_agg AS
SELECT 
  DATE(job_posted_date) AS posted_date,
  job_work_from_home,
  COUNT(*) AS posting_count,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY DATE(job_posted_date), job_work_from_home;

-- Dashboard query (now <100ms, hits the view)
SELECT * FROM job_postings_daily_agg
WHERE posted_date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY posted_date DESC, job_work_from_home;

-- Refresh hourly (pseudocode—implementation varies by DB)
REFRESH MATERIALIZED VIEW job_postings_daily_agg;
```

## Notes

- **Staleness vs. freshness contract:** Define acceptable lag before choosing refresh frequency. Hourly works for dashboards; real-time fraud detection needs incremental updates or streaming, not batch materialised views.
- **Incremental refresh trade-off:** Full refresh rewrites the entire view; incremental refresh (insert/update only changes since last run) is faster but requires tracking change timestamps and is more complex to implement correctly.
- **Index the materialised view:** Materialised views are tables—add indexes on commonly filtered columns (e.g., `posted_date`, `job_work_from_home`) to keep dashboard queries fast.
- **Watch for cascading staleness:** If your materialised view depends on *another* materialised view, refresh order matters. View A must refresh before View B, or B remains stale. Use dependency graphs and orchestrate with DAGs (Airflow, dbt).
- **Adjacent: incremental models (dbt) and CDC:** dbt's incremental models achieve similar goals; change data capture (CDC) pipes only new/modified rows into a warehouse, enabling near-real-time materialisation without full rescans.
