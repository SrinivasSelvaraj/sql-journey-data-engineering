---
date: 2026-08-25
phase: sql
topic: Approximate aggregates: HyperLogLog and sketch-based cardinality
---

# Approximate aggregates: HyperLogLog and sketch-based cardinality

*SQL for analytics and engineering*

## Concept

Exact cardinality counts become prohibitively expensive at scale. A query like `SELECT COUNT(DISTINCT user_id) FROM events WHERE date > '2024-01-01'` must materialize every unique ID in memory or disk, then count. On billions of rows across distributed systems, this is slow and resource-intensive. HyperLogLog and other sketch data structures trade precision for speed and memory: they estimate cardinality with tunable accuracy (typically 1–2% error) using constant or near-constant space, regardless of input size.

HyperLogLog works by hashing inputs and tracking the position of the first 1-bit in the hash output. Different inputs scatter across a fixed number of buckets, and the maximum leading-zero count per bucket estimates the unique count logarithmically. This is crucial when you need to answer "how many distinct X?" on fact tables with billions of rows, especially in real-time dashboards, streaming aggregates, or when combining cardinality estimates across shards.

The cost of ignoring this: slow materialization queries that time out, expensive shuffle operations in distributed engines, memory pressure on analytics clusters, and inability to estimate cardinality incrementally. Many modern data warehouses (Snowflake, BigQuery, DuckDB) expose HyperLogLog or similar functions natively.

## Practice

**Problem:** You need to report the approximate number of distinct job locations across all job postings, and the exact count is too slow for a dashboard that refreshes every 15 minutes. Use HyperLogLog to estimate cardinality efficiently.

```sql
-- Approach 1: Build a sketch and estimate cardinality (Snowflake/BigQuery syntax)
SELECT
  APPROX_COUNT_DISTINCT(job_location) AS approx_distinct_locations
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY;

-- Approach 2: If you need to merge estimates across time windows or partitions
-- (e.g., daily aggregate then roll up)
SELECT
  DATE_TRUNC('DAY', job_posted_date) AS day,
  HLL_INIT_AGG(job_location) AS location_sketch  -- build sketch per day
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 7 DAY
GROUP BY DATE_TRUNC('DAY', job_posted_date);

-- Then merge and estimate:
SELECT
  HLL_MERGE_AGGS(location_sketch) AS merged_sketch,
  HLL_ESTIMATE_AGG(merged_sketch) AS approx_total_locations
FROM <above query>;

-- Approach 3: Compare approximate vs. exact (small dataset validation)
SELECT
  APPROX_COUNT_DISTINCT(job_location) AS approx_count,
  COUNT(DISTINCT job_location) AS exact_count
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - 1  -- single day for quick validation
ORDER BY approx_count;
```

## Notes

- **Exact vs. approximate trade-off:** Use `APPROX_COUNT_DISTINCT` in dashboards and reporting; use exact `COUNT(DISTINCT)` only when precision is required and cardinality is manageable (<10M unique values).
- **Mergeable sketches matter:** HyperLogLog's killer feature is that sketches can be combined without re-scanning raw data. If you pre-aggregate daily sketches, you can estimate weekly/monthly totals in milliseconds.
- **Accuracy depends on cardinality:** HyperLogLog accuracy improves as cardinality grows; on small sets (<1000 unique values), the 1–2% error floor can dominate. Run sanity checks on pilot queries.
- **Syntax varies by engine:** Snowflake uses `HLL_INIT_AGG`, `HLL_MERGE_AGGS`, and `HLL_ESTIMATE_AGG`; BigQuery uses `APPROX_COUNT_DISTINCT` directly; DuckDB and PostgreSQL have similar functions but different names—always check docs.
- **Adjacent topics:** Bloom filters (set membership testing), Count-Min Sketch (frequency estimation), and quantile sketches (approximate percentiles). Cardinality estimation is a gateway to probabilistic data structures.
