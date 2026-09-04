---
date: 2026-09-04
phase: cloud
topic: Caching layers: CloudFront, CDN and local caching trade-offs
---

# Caching layers: CloudFront, CDN and local caching trade-offs

*Cloud platforms and storage*

## Concept

Caching layers sit between your application and data source, storing frequent queries or assets to reduce latency and database load. CloudFront (AWS CDN) caches HTTP responses at edge locations; local caching (Redis, Memcached, application memory) stores hot data near your compute. The trade-off is immediate: cache hits are sub-millisecond but misses add latency; stale data risks correctness; cache invalidation is hard and expensive. Without caching, a popular dashboard querying 50M rows refreshing every 5 minutes can cost 10× more in database compute and leave users waiting 2–5 seconds per load. With it, you shift cost to storage (cache footprint) and operational complexity (invalidation logic).

When you query the same aggregation repeatedly—job salary statistics by location, counts of remote positions—you're doing wasteful work. CloudFront helps for static or semi-static assets and cacheable API responses (set `Cache-Control` headers); it doesn't help with personalized or real-time data. Local in-process or Redis caching is better for dynamic, frequently-accessed computed values. The breaking point arrives when cache TTL doesn't match data freshness: if you cache job postings for 1 hour but jobs update every 5 minutes, stale data flows to users. Similarly, if you cache at the CDN layer but never invalidate on data changes, you're serving yesterday's salary rankings.

## Practice

**Problem:** A dashboard displays average salary by job location, refreshed every 10 minutes by 500 concurrent users. Naive query runs 2s, scans 12M rows. CloudFront alone won't help (personalized by location). You need to cache the aggregated results in Redis, keyed by location, with invalidation on new job postings.

```sql
-- Precompute and cache (run every 10 min via scheduled job)
WITH location_stats AS (
  SELECT 
    job_location,
    COUNT(*) as job_count,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) as median_salary,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY salary_year_avg) as p90_salary,
    ROUND(100.0 * SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) / COUNT(*), 1) as remote_pct
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
  GROUP BY job_location
)
SELECT * FROM location_stats;

-- Application pseudocode:
-- cache_key = f"job_stats:{location}"
-- result = redis.get(cache_key)
-- if result is None:
--   result = query_above_from_database()
--   redis.setex(cache_key, 600, result)  -- TTL 10 min
-- return result
```

## Notes

- **Cache invalidation timing mismatch:** Setting TTL=3600s but data changes every 5 minutes creates stale results. Align TTL to your SLA for freshness, not convenience. Use event-driven invalidation (trigger cache clear on INSERT to job_postings_fact) for critical data.
- **CDN layer confusion:** CloudFront caches HTTP responses, not database rows. It's useful for static job listing pages or an API endpoint that wraps your aggregation query with long Cache-Control headers, but adds 50–200ms round-trip to cold misses.
- **Cache stampede risk:** When a key expires and 100 requests hit your Redis simultaneously, all 100 may query the database. Use locking (Redis `SET NX`) or probabilistic expiration to prevent thundering herd.
- **Local memory vs. Redis:** In-process caching (Python dict, JVM heap) is faster but not shared across instances; Redis is shared but adds network latency (~1ms). For dashboards, prefer Redis. For hot row lookups in tight loops, local cache with manual invalidation.
- **Revisit:** Cost analysis (cache storage + invalidation logic vs. database spend), cache key design (avoid cardinality explosion), and observability (cache hit rates, eviction metrics in CloudWatch/Datadog).
