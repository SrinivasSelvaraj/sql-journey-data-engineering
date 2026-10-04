---
date: 2026-10-04
phase: sql
topic: Query result caching and materialized view staleness
---

# Query result caching and materialized view staleness

*SQL for analytics and engineering*

## Concept

Query result caching and materialized view staleness represent a fundamental tradeoff in analytics: **speed vs. freshness**. When you cache a query result or materialize a view, you store a pre-computed snapshot to avoid recomputing expensive aggregations. However, as the underlying tables change, your cached result diverges from ground truth. The staleness window—how far behind reality your cache lags—depends on your refresh strategy (full refresh, incremental refresh, or event-triggered refresh).

This matters most when: (1) the same expensive query runs repeatedly within a time window where stale data is acceptable, (2) you have slow aggregations over large tables (e.g., rolling averages across millions of rows), or (3) dashboard queries would otherwise timeout. It breaks silently when stakeholders don't know the cache lag and make decisions on yesterday's numbers, or when you refresh so infrequently that the cache becomes a liability rather than an asset.

The key insight: **caching is a business decision, not just a technical one.** A materialized view refreshed hourly is correct for daily business reviews but catastrophic for real-time fraud detection. Query result caching also interacts with query plan optimization—a cached result bypasses the query engine entirely, so slow underlying logic never gets exposed or fixed.

## Practice

**Problem:** You manage a dashboard showing average salary by job title for remote positions, refreshed daily at 2 AM. Users complain that their 11 PM decision uses stale data. Write a query that computes the materialized view AND a companion query that estimates how many *new* remote job postings arrived since the last refresh (assume the view was refreshed at 2 AM today).

```sql
-- Materialized view definition (refreshed nightly at 2 AM)
CREATE MATERIALIZED VIEW mv_remote_salary_by_title AS
SELECT 
  job_title_short,
  COUNT(*) AS job_count,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary,
  MAX(job_posted_date) AS last_job_posted
FROM job_postings_fact
WHERE job_work_from_home = TRUE
GROUP BY job_title_short;

-- Companion query: estimate staleness at query time
-- Assumes refresh happens at 2024-01-15 02:00:00
SELECT 
  job_title_short,
  COUNT(*) AS new_postings_since_refresh,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary_of_new_postings,
  CURRENT_TIMESTAMP - TIMESTAMP '2024-01-15 02:00:00' AS time_since_refresh
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_posted_date > '2024-01-15'::DATE
GROUP BY job_title_short
ORDER BY new_postings_since_refresh DESC;
```

The materialized view serves fast reads; the companion query quantifies staleness in real time, letting users decide if the cache is fresh enough for their decision.

## Notes

- **Refresh strategy matters more than technology:** Hourly full refresh of a 100 GB view can be slower and more resource-intensive than event-triggered incremental refresh. Know your SLA first.
- **Staleness is often invisible:** A materialized view doesn't flag that it's stale. Always expose refresh timestamp and lag metrics in your BI layer or query output.
- **Cache invalidation is one of the two hard problems in computer science:** For dimensions that change slowly (job titles, locations), materialized views work well. For fast-moving facts (salary data, new postings), invalidation becomes a bottleneck.
- **Connects to:** query plan optimization (caching bypasses planning), incremental/CDC patterns (more sophisticated refresh strategies), and monitoring (you need alerts on refresh failures and lag).
- **Revisit:** the difference between materialized views (persistent, managed by DB) vs. query-result caches (temporary, often in application layer or Redis), and how each interacts with transaction isolation levels.
