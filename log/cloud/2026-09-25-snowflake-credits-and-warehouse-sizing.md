---
date: 2026-09-25
phase: cloud
topic: Snowflake credits and warehouse sizing
---

# Snowflake credits and warehouse sizing

*Cloud platforms and storage*

## Concept

Snowflake credits measure compute consumption: one credit = one virtual warehouse running for one hour. Your bill depends on warehouse *size* (number of credits per hour) and *duration* (how long it runs). A large warehouse (e.g., L = 8 credits/hour) costs 8× more per minute than a small one (XS = 1 credit/hour), but may finish a query 4–5× faster, potentially using fewer total credits. Without understanding this tradeoff, you either overspend on oversized warehouses or waste time waiting for undersized ones to churn through data.

Query performance directly ties to warehouse size: larger warehouses have more parallel processing power. A slow query on an XS warehouse might complete in seconds on an L warehouse—but if you're running 100 tiny queries daily on L when XS would suffice, you're hemorrhaging credits. The cost-per-query isn't fixed; it's a function of size, data volume, and operation complexity (full scans, joins, and aggregations are expensive; simple filters and projections are cheap).

## Practice

**Problem:** You notice job_postings_fact queries are consistently slow and expensive. A full scan of 5M rows with aggregation runs in 20 minutes on an XS warehouse. You need to determine if scaling up saves money overall, and identify which queries are credit hogs.

```sql
-- Estimate credits burned by current query on XS (1 credit/hr)
SELECT 
  COUNT(*) as row_count,
  20 / 60.0 as hours_on_xs,
  ROUND(20 / 60.0 * 1, 2) as credits_xs,
  ROUND(20 / 60.0 * 8, 2) as credits_large_estimate
FROM job_postings_fact;

-- Actual: run same query on L warehouse to measure real time
-- L warehouse query completes in 6 minutes = 0.1 hours
-- Cost: 0.1 * 8 = 0.8 credits (vs 0.33 on XS for 20 min)
-- But if you run this query 50×/day: XS = 16.5 credits/day, L = 40 credits/day

-- Smart approach: push filtering to reduce data scanned
SELECT 
  job_title_short,
  ROUND(AVG(salary_year_avg), 2) as avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - 30  -- filter first
  AND job_location != 'N/A'
GROUP BY job_title_short
ORDER BY avg_salary DESC;
-- This scans ~500K rows instead of 5M, runs fast even on XS
```

## Notes

- **Suspend, don't delete:** Always suspend warehouses after use rather than deleting them—resuming is instant and free, but recreation incurs startup overhead. Set auto-suspend to 2–5 minutes for dev/test.
- **Query profile is your friend:** Use `EXPLAIN` and Snowflake's query profiler to spot full table scans, cross joins, and data skew. A 10-second query on L can become 2 seconds with better predicates—same query, 4× cheaper.
- **Compute vs. storage costs:** Credits only pay for compute (warehouses). Storage (per TB/month) is separate and cheap (~$4/TB for on-demand). Aggressive partitioning and clustering reduce *scanned* data, lowering credits without touching storage.
- **Warehouse pooling and scaling policies:** For variable workloads, consider scaling policies (auto-scale to max size based on queue depth) or resource monitors to cap daily/monthly spending.
- **Adjacent topics:** Query caching (avoid re-running identical queries), result clustering, and materialized views all reduce credit spend without changing warehouse size.
