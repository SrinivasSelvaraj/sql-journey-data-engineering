---
date: 2026-10-14
phase: cloud
topic: Snowflake credit consumption: factors and optimization
---

# Snowflake credit consumption: factors and optimization

*Cloud platforms and storage*

## Concept

Snowflake charges credits based on compute (warehouse size and duration) and storage (average monthly data stored), not query volume or data scanned. A single poorly-written query on a large warehouse can cost more than dozens of optimized queries, making credit consumption visibility critical for controlling cloud costs. Understanding what drives consumption—warehouse size, query complexity, auto-suspend settings, and full table scans—lets you distinguish between "the query is slow" and "the query is expensive."

Credit optimization directly impacts both cost and performance. A query that runs 10 seconds on an XL warehouse (8 credits/hour) costs ~0.022 credits, but the same query on a 3XL warehouse (24 credits/hour) costs ~0.067 credits. Equally important: scanning 100 GB when you only need 1 GB wastes compute time and credits. Without monitoring query profiles and warehouse utilization, you'll overspend on both oversized warehouses and unoptimized queries that could finish faster on smaller warehouses with better filtering.

## Practice

**Problem:** A data analyst runs daily reports filtering `job_postings_fact` by location and date, but the query consumes 3x more credits than expected. The warehouse is sized at Medium (4 credits/hour) and queries often take 5+ minutes. How do you identify and fix the credit waste?

```sql
-- SLOW/EXPENSIVE: Full table scan, no pruning
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_location LIKE '%New York%'
  AND YEAR(job_posted_date) = 2024;

-- OPTIMIZED: Partition pruning, explicit date range, index-friendly predicates
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_location = 'New York, NY'  -- Exact match, not LIKE
  AND job_posted_date >= '2024-01-01'
  AND job_posted_date < '2024-12-31'
ORDER BY job_posted_date DESC
LIMIT 1000;

-- DIAGNOSTIC: Check query profile for full-table scans and compute time
SELECT *
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER())
WHERE USER_NAME = 'analyst'
  AND QUERY_TEXT ILIKE '%job_postings_fact%'
ORDER BY START_TIME DESC
LIMIT 5;
```

The optimized version avoids full-table scans via date range predicates, uses exact string matching instead of LIKE (cheaper to evaluate), and reduces output volume with LIMIT. Always review the query profile to confirm Snowflake is pruning partitions.

## Notes

- **Warehouse auto-suspend timing:** Default 10 minutes auto-suspend can waste credits if you have frequent small queries. Tune based on usage patterns (interactive sessions vs. batch jobs).
- **Materialized views vs. queries:** Pre-compute and store expensive aggregations; the storage cost is often lower than recomputing credits repeatedly.
- **Clustering keys:** Define on high-cardinality columns commonly filtered (e.g., `job_location`, `job_posted_date`) to enable micro-partition pruning and cut bytes scanned.
- **Query results caching:** Identical queries within 24 hours reuse results for free; useful for dashboards but misleading when benchmarking query speed.
- **Adjacent topics:** Query profiling (QUERY_PROFILE), resource monitors (credit limits and alerts), and cost allocation (tagging warehouses by department/project).
