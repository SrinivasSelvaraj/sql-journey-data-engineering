---
date: 2026-10-14
phase: cloud
topic: Snowflake result caching: TTL and cost savings
---

# Snowflake result caching: TTL and cost savings

*Cloud platforms and storage*

## Concept

Snowflake caches query results in memory for 24 hours by default (configurable via `RESULT_CACHE_MAX_AGE`), returning cached results instantly without scanning underlying data or consuming credits. This dramatically reduces query latency and cost when identical queries run repeatedly—common in dashboards, reporting jobs, and analytical workloads where the same aggregations execute every hour or every few hours.

Result caching is transparent and automatic, but it breaks if you modify source tables, change query text even slightly (whitespace, comments, or clause order differences invalidate the cache), or disable it explicitly. It does not apply to non-deterministic functions like `CURRENT_TIMESTAMP()` or `RANDOM()`, and it respects role-based access control, so cached results for one user won't be reused by another user without permission to the underlying tables.

Understanding when caching applies matters because it's the difference between a query costing $0.01 (cached, no compute) and $2.00+ (full scan). For cost tracking and performance debugging, you need to check the `IS_RESULT_CACHED` column in `QUERY_HISTORY` to know whether Snowflake actually used the cache or executed the full computation.

## Practice

**Problem:** You run a daily dashboard that aggregates salary statistics for remote job postings. The query runs every hour and always returns the same result. You want to avoid scanning millions of rows repeatedly and understand how much you're saving.

```sql
-- Check whether results are cached
SELECT 
  query_id,
  query_text,
  total_elapsed_time / 1000 AS elapsed_sec,
  is_result_cached,
  credits_used_compute
FROM snowflake.account_usage.query_history
WHERE query_text LIKE '%job_postings_fact%salary%remote%'
  AND start_time > CURRENT_DATE - 7
ORDER BY start_time DESC;

-- The actual dashboard query (identical each run = cache hit)
SELECT 
  job_work_from_home,
  COUNT(*) AS job_count,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary,
  ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg), 2) AS median_salary
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_posted_date >= CURRENT_DATE - 30
GROUP BY job_work_from_home;
```

The first query shows whether `IS_RESULT_CACHED` is true; if so, `ELAPSED_SEC` drops to <1s and `CREDITS_USED_COMPUTE` approaches zero on subsequent runs, proving the cache is working.

## Notes

- **Whitespace and comments matter**: `SELECT * FROM tbl` and `SELECT * FROM tbl --comment` are different queries; cache won't match. Use consistent formatting or query templates to maximize hit rates.
- **24-hour default TTL is aggressive**: For slowly-changing reference data, consider `CREATE ICEBERG TABLE` or materialized views instead; for high-velocity data, reduce `RESULT_CACHE_MAX_AGE` or disable caching on that table with `ALTER TABLE tbl SET RESULT_CACHE_MAX_AGE_DAYS = 0`.
- **Non-deterministic functions break caching**: Any query with `NOW()`, `CURRENT_TIMESTAMP()`, `RANDOM()`, or `GETDATE()` will never cache. Parameterize dates as inputs instead to preserve cache eligibility.
- **Connects to**: query profiling (`EXPLAIN`), materialized views for permanent aggregations, clustering keys for scan optimization, and warehouse sizing (caching reduces the need for larger, faster warehouses).
- **Revisit**: result caching interacts with cloning (cloned tables share the parent's cache), fail-safe retention windows (cached data is not in fail-safe), and multi-statement transactions (cache is checked per statement, not per transaction).
