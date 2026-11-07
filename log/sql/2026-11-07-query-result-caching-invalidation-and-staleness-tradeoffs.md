---
date: 2026-11-07
phase: sql
topic: Query result caching: invalidation and staleness tradeoffs
---

# Query result caching: invalidation and staleness tradeoffs

*SQL for analytics and engineering*

## Concept

Query result caching stores the output of expensive computations (aggregations, joins, window functions) to avoid recomputation. Without it, every identical query re-executes, wasting CPU and I/O. However, caching introduces **staleness**: cached results diverge from the underlying data as new rows are inserted or existing rows updated. The core tradeoff is freshness vs. speed—a 2-hour-old cached dashboard is fast but may mislead decisions if the underlying job_postings_fact table received 50,000 new rows today.

Invalidation strategy determines when cached results become unreliable. Time-based invalidation (TTL) is simple but crude: you might serve stale data for 30 minutes even though the source changed in the first minute. Event-based invalidation (cache bust on INSERT/UPDATE to source tables) is more precise but requires dependency tracking and coordination. Most production systems layer both: a 15-minute TTL with manual invalidation for critical dashboards after bulk loads.

Without explicit caching strategy, analytics teams either accept slow queries or accidentally build decisions on data they don't realize is stale. Query plans hide this problem—a 45-second query might run daily but users assume it's always current.

## Practice

**Problem:** You're building a cached dashboard showing average salary by job location. The underlying job_postings_fact table receives new postings hourly. Write a query that would be safe to cache with a 6-hour TTL, and explain what rows you'd need to invalidate the cache early.

```sql
-- Cacheable query: include metadata for invalidation logic
SELECT 
  job_location,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary,
  COUNT(*) AS posting_count,
  MAX(job_posted_date) AS last_update_timestamp
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
  AND job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY
GROUP BY job_location
ORDER BY avg_salary DESC;

-- Invalidation trigger logic (pseudocode):
-- If any INSERT/UPDATE on job_postings_fact WHERE job_posted_date = TODAY(),
-- invalidate cache immediately rather than waiting 6 hours.
-- If job_posted_date is backfilled (historical correction), 
-- compare MAX(job_posted_date) in cache vs. fresh query—if they differ, invalidate.
```

The `MAX(job_posted_date)` column lets downstream systems detect staleness: if the dashboard was cached at 2pm and you query at 2:30pm, compare the cached timestamp to the current maximum. If new data arrived, invalidate.

## Notes

- **TTL alone is risky for analytics**: A 24-hour cache on "sales by region" during Q4 can skew decisions by hours. Pair TTL with event-based invalidation on high-velocity tables.
- **Partial invalidation is underutilized**: Instead of clearing the entire cached result, invalidate only the job_location partition that changed. Requires extra complexity but saves recomputation of stable regions.
- **Staleness is asymmetric**: Adding rows (new job postings) changes aggregates smoothly; correcting or deleting historical rows can cause sharp jumps that queries and dashboards should flag as anomalies.
- **Query plan doesn't reveal cache hits**: EXPLAIN ANALYZE shows how the query runs, not whether it was cached. Monitor cache hit rates separately (cache layer logs, query execution times).
- **Adjacent: materialized views** pre-compute and refresh on a schedule, trading storage for guaranteed freshness windows. **Also revisit: incremental aggregation** (append-only deltas) to minimize recomputation on large fact tables.
