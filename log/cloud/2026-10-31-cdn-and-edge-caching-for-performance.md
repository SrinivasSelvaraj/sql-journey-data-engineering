---
date: 2026-10-31
phase: cloud
topic: CDN and edge caching for performance
---

# CDN and edge caching for performance

*Cloud platforms and storage*

## Concept

A Content Delivery Network (CDN) caches static assets and frequently accessed data at geographically distributed edge servers, reducing latency by serving content from a location close to the user rather than from a distant origin. This matters most when your application serves the same data repeatedly to many users across regions—images, stylesheets, API responses, or pre-computed query results. Without edge caching, every request traverses the full network path to your origin, incurring latency tax that compounds across millions of requests and becomes especially painful for users far from your data center.

In data engineering, CDN thinking applies beyond web assets: materialized views, query result caches, and static datasets benefit from edge placement. When your BI dashboard queries a 100GB table for the same aggregation dozens of times per day, you're paying for recomputation and network I/O each time. A CDN strategy—or its data equivalent, a cache layer—collapses that to one computation plus cheap cache hits.

The cost model is critical: you pay for origin bandwidth egress, cache storage at each edge location, and request volume. Misconfigured caches (short TTLs, overly broad invalidation, wrong granularity) defeat the economics. Understanding what *should* be cached versus what *must* be fresh is the engineering problem.

## Practice

**Problem:** A job search API returns `job_postings_fact` filtered by location and work-from-home status. The same filters run thousands of times daily (e.g., "remote jobs in tech"), but the underlying data updates once per night. Currently, each request rescans the fact table, causing slow queries and high compute bills.

```sql
-- Cache key: location + work_from_home + date bucket
-- Materialized view updated nightly, served from cache layer
CREATE MATERIALIZED VIEW job_postings_cache AS
SELECT 
  job_location,
  job_work_from_home,
  DATE_TRUNC('day', job_posted_date) AS posted_day,
  COUNT(*) AS job_count,
  ROUND(AVG(salary_year_avg)::numeric, 0) AS avg_salary,
  ARRAY_AGG(DISTINCT job_title_short) AS job_titles
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY job_location, job_work_from_home, DATE_TRUNC('day', job_posted_date);

-- API queries cache instead of fact table
SELECT * FROM job_postings_cache
WHERE job_location = 'San Francisco, CA' 
  AND job_work_from_home = TRUE;
```

The cache is refreshed once daily (or on ingest), and the API serves warm results in milliseconds instead of rescanning millions of rows.

## Notes

- **TTL misalignment:** Setting cache TTL too short defeats the purpose (constant invalidation overhead); too long surfaces stale data. Match TTL to your SLA and update frequency, not guesswork.
- **Cache invalidation is hard:** Monitor what's actually being cached vs. what you think is cached; uneven hit rates signal poorly chosen cache keys or overly granular partitioning.
- **Origin bottleneck:** Caching only helps if the origin can handle the spike when caches expire simultaneously. Stagger invalidation or use probabilistic expiration (XFetch, stale-while-revalidate headers).
- **Adjacent: query result caching, data warehousing tiers (hot/warm/cold), and request coalescing.** This connects to understanding your query patterns before optimizing storage.
- **Measure before caching:** Run slow-query logs and request frequency analysis first. Caching the wrong thing wastes money and adds latency-hiding complexity.
