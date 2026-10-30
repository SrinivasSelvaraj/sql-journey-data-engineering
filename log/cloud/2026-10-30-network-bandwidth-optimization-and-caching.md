---
date: 2026-10-30
phase: cloud
topic: Network bandwidth optimization and caching
---

# Network bandwidth optimization and caching

*Cloud platforms and storage*

## Concept

Network bandwidth is the throughput between your compute layer and storage layer—measured in GB/s or cost per GB transferred. Every byte crossing the network costs money (especially in cloud) and latency (especially over distance). Caching layers (Redis, Memcached, query result sets) sit between compute and storage to serve hot data locally, avoiding repeated remote fetches. Without optimization, a single analytical query scanning 500GB across regions can cost $25–50 and take minutes; with caching, the same query on cached aggregates hits in milliseconds for pennies.

What breaks: slow dashboards that query raw fact tables repeatedly, high cloud egress bills, inefficient joins across partitions or regions, and loading entire datasets when you only need summaries. The root cause is often invisible—you see latency but not that 80% of it is network round-trips, not computation.

## Practice

**Problem:** A dashboard queries `job_postings_fact` daily to show average salary by job title. Without optimization, the query scans 50M rows across network and recalculates the same aggregation 100 times per day.

```sql
-- INEFFICIENT: Full table scan, repeated aggregation
SELECT 
  job_title_short, 
  AVG(salary_year_avg) AS avg_salary,
  COUNT(*) AS job_count
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY job_title_short;

-- OPTIMIZED: Pre-aggregate into materialized view (cache)
CREATE MATERIALIZED VIEW job_salary_summary AS
SELECT 
  job_title_short,
  AVG(salary_year_avg) AS avg_salary,
  COUNT(*) AS job_count,
  MAX(job_posted_date) AS last_updated
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY job_title_short;

-- Dashboard queries the cache instead
SELECT * FROM job_salary_summary;

-- Refresh incrementally (partition-aware, only new data)
REFRESH MATERIALIZED VIEW CONCURRENTLY job_salary_summary;
```

## Notes

- **Egress costs are hidden**: AWS charges $0.02/GB out of region; sum that across 1000 queries and it exceeds compute cost. Always check CloudTrail or cost breakdown by service.
- **Caching isn't free**: Stale data, cache invalidation overhead, and storage costs. Only cache what's queried repeatedly (80/20 rule).
- **Partition pruning > caching**: Filter by date/region at query time before relying on caching. Combine both—query partitions, then cache results.
- **Cold start problem**: First query after cache refresh is slow. Use warming queries or scheduled refreshes during off-peak hours.
- **Adjacent topics**: columnar compression (Parquet), query result caching (Athena, BigQuery), CDN patterns, and connection pooling.
