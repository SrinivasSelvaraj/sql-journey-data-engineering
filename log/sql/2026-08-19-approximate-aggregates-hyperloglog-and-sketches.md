---
date: 2026-08-19
phase: sql
topic: Approximate aggregates: HyperLogLog and sketches
---

# Approximate aggregates: HyperLogLog and sketches

*SQL for analytics and engineering*

## Concept

Approximate aggregates like HyperLogLog are probabilistic data structures that trade exact answers for dramatic space and speed improvements. Instead of materializing millions of distinct user IDs to count them, HyperLogLog estimates cardinality in kilobytes with ~2% error. This matters when you're counting distinct values at scale (distinct users across billions of events, unique IPs in logs) where exact counts either timeout or consume prohibitive memory.

Without sketches, a `SELECT COUNT(DISTINCT user_id)` query over a fact table with 10 billion rows forces the database to either build an in-memory hash table (OOM risk), spill to disk (slow), or scan the entire dataset. With HyperLogLog, databases like Redshift, BigQuery, and Druid can answer in milliseconds using a fixed-size sketch regardless of cardinality. The tradeoff is acceptable because in analytics, *approximate* distinct counts are usually good enough—knowing you have "roughly 5M users" not "5,000,001" is actionable.

The key insight: sketches give you sublinear space complexity. HyperLogLog uses O(log log n) bytes, Count-Min Sketch estimates heavy hitters, and T-Digest approximates quantiles. These are essential when exact aggregates aren't cost-justified.

## Practice

**Problem:** You need to track approximate distinct job titles across all postings to understand market diversity. An exact distinct count times out on the 50M row table. Use a sketch-based approach if available in your system, then show the conventional fallback.

```sql
-- Modern approach: HyperLogLog sketch (Redshift, BigQuery, Druid)
SELECT APPROX_COUNT_DISTINCT(job_title_short) AS approx_unique_titles
FROM job_postings_fact;

-- Fallback for older systems: count distinct with LIMIT + sampling
-- (Less accurate, but avoids OOM)
SELECT COUNT(DISTINCT job_title_short) AS exact_unique_titles
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY;

-- If you must track distinct *and* aggregate: use HyperLogLog in a sketch column
-- (Assumed pre-computed in a materialized view or real-time pipeline)
SELECT 
  job_work_from_home,
  APPROX_COUNT_DISTINCT(job_id) AS approx_unique_jobs,
  COUNT(*) AS total_postings,
  AVG(salary_year_avg) AS avg_salary
FROM job_postings_fact
GROUP BY job_work_from_home;
```

## Notes

- **Precision vs. performance trade:** HyperLogLog introduces ~2% relative error by design. If your SLA requires 100% accuracy (e.g., billing), you need exact counts; if it's dashboards, sketches win.
- **Sketch mergability:** One huge advantage is that HyperLogLog sketches from different time windows or partitions can be merged cheaply—critical for distributed systems. Count-Min Sketch has similar properties for frequency estimation.
- **Common mistake:** Confusing `APPROX_COUNT_DISTINCT` with `COUNT(DISTINCT)` in performance analysis. The former is O(n) scan + O(log log n) memory; the latter is O(n) scan + O(n) memory in worst case. Never use approximate functions for correctness-critical joins or row-level filtering.
- **Related topics:** Connects to cardinality estimation in query planning, sampling strategies (when approximation isn't available), and bloom filters (for membership testing, not counting).
- **Revisit when:** You implement incremental aggregation in a streaming pipeline (Kafka → real-time sketch), or design a metrics system where you need distinct counts across billions of events in sub-second latency.
