---
date: 2026-10-24
phase: sql
topic: Query result caching and invalidation strategies
---

# Query result caching and invalidation strategies

*SQL for analytics and engineering*

## Concept

Query result caching stores the output of expensive SQL queries so repeated identical requests return instantly instead of rescanning tables. In analytics and dashboards, the same aggregations run hundreds of times per day—caching eliminates redundant computation. However, cached results are only valid until the underlying data changes; stale caches serve incorrect numbers, silently breaking business decisions.

Invalidation strategy determines *when* to discard a cache entry. Time-based (TTL) invalidation expires results after N minutes, trading freshness for simplicity. Event-based invalidation watches for INSERT/UPDATE/DELETE on source tables and immediately purges affected caches, requiring explicit dependency tracking. Most production systems use hybrid approaches: short TTLs for frequently-changing fact tables, longer ones for slowly-changing dimensions.

Without a coherent strategy, you either waste compute running queries that could be cached, or serve stale data that corrupts analytics and metrics. The cost is highest when caching spans multiple dashboards or reports—one invalidated query invalidates dozens of dependent caches downstream.

## Practice

**Problem:** You maintain a dashboard showing average salary by job title, refreshed every 15 minutes. The `job_postings_fact` table receives new postings continuously throughout the day. Currently queries run even when no new data arrived. Design a caching and invalidation approach that balances freshness and compute cost.

```sql
-- Cache query: compute once, store result
WITH salary_by_title AS (
  SELECT 
    job_title_short,
    COUNT(*) as posting_count,
    ROUND(AVG(salary_year_avg), 2) as avg_salary,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg), 2) as median_salary
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
    AND salary_year_avg IS NOT NULL
  GROUP BY job_title_short
  ORDER BY avg_salary DESC
)
SELECT *, CURRENT_TIMESTAMP as cache_generated_at
INTO job_salary_cache
FROM salary_by_title;

-- Invalidation trigger: on new posting, update cache timestamp
CREATE TRIGGER invalidate_salary_cache
AFTER INSERT ON job_postings_fact
EXECUTE FUNCTION update_cache_timestamp('job_salary_cache');

-- Query-time check: use cache only if fresh
SELECT *
FROM job_salary_cache
WHERE cache_generated_at > CURRENT_TIMESTAMP - INTERVAL '15 minutes'
UNION ALL
SELECT job_title_short, COUNT(*), ROUND(AVG(salary_year_avg), 2), 
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg), 2),
       CURRENT_TIMESTAMP
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
  AND salary_year_avg IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM job_salary_cache WHERE cache_generated_at > CURRENT_TIMESTAMP - INTERVAL '15 minutes')
GROUP BY job_title_short;
```

## Notes

- **Dependency hell:** Caching one query isn't enough—track all downstream queries that depend on it. Invalidating the base query must cascade through all dependents, or intermediate caches become inconsistent.
- **Cache-aside vs. write-through:** Cache-aside (check cache, compute on miss) is simpler but has cold-start latency. Write-through (always update cache on data change) guarantees freshness but adds write latency. Choose based on read/write ratio.
- **Partial invalidation matters:** Don't invalidate the entire cache if only one date partition changed. Tagging cache entries by table, time range, or dimension filter (e.g., "job_postings WHERE job_posted_date > 2024-01-15") lets you invalidate surgically.
- **Tools and systems:** Redis, Memcached, and database materialized views handle different scales. Materialized views work within one DB; external caches (Redis) work across distributed systems. Data warehouses (Snowflake, BigQuery) offer incremental refresh and clustering to avoid needing external caches for many use cases.
- **Monitor staleness:** Always log cache hit/miss rates and age distribution. A 99% hit rate on 6-hour-old results is worse than 50% hit rate on fresh data. Set up alerts when cache drift exceeds SLA.
