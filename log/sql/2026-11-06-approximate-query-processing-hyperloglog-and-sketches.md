---
date: 2026-11-06
phase: sql
topic: Approximate query processing: HyperLogLog and sketches
---

# Approximate query processing: HyperLogLog and sketches

*SQL for analytics and engineering*

## Concept

Approximate query processing trades absolute accuracy for dramatic speed and memory gains when exact answers aren't required. **HyperLogLog** is a probabilistic data structure that estimates cardinality (distinct count) using only O(log log N) memory instead of O(N), introducing a configurable error margin (typically 0–2%). **Sketches** generalize this approach—compact summaries that support approximate answers to aggregation queries: COUNT DISTINCT, percentiles, frequent items, and range queries.

In analytics, you rarely need an exact distinct count of 10,487,392 when "approximately 10.5 million" suffices and runs 100× faster. Sketch-based systems (Druid, Pinot, some modern data warehouses) pre-compute HyperLogLog structures during ingestion, making real-time cardinality queries sub-second. Without approximation, COUNT(DISTINCT user_id) over billions of rows forces full table scans and hash aggregation—prohibitive for interactive dashboards or exploratory queries on streaming data.

The trade-off breaks when precision matters: financial audits, exact inventory counts, or compliance queries cannot use approximations. Understanding the error bounds and when your system applies sketches (vs. exact aggregation) is critical for correct conclusions.

## Practice

**Problem:** Your analytics team wants to monitor distinct job locations in real-time across millions of postings without slowing the dashboard. Build a query that estimates unique job locations, then compare performance implications with an exact COUNT(DISTINCT).

```sql
-- Approximate approach (using HyperLogLog if your system supports it)
-- Example: Redshift, Snowflake, or systems with HLL functions
SELECT
  APPROX_COUNT_DISTINCT(job_location) AS approx_unique_locations,
  COUNT(*) AS total_postings
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7 days';

-- Exact approach (for comparison—slower on large datasets)
SELECT
  COUNT(DISTINCT job_location) AS exact_unique_locations,
  COUNT(*) AS total_postings
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7 days';

-- If your system has explicit HyperLogLog functions (e.g., PostgreSQL with hll extension):
-- SELECT HLL(job_location)::hlltype AS location_sketch FROM job_postings_fact;
```

The approximate query scales linearly with cardinality, not data volume; the exact query requires sorting/hashing all distinct values. For 100M rows across 50k locations, approximate finishes in milliseconds; exact may take seconds.

## Notes

- **Common mistake:** Treating approximate results as exact without documenting error bounds. Always state "±2% error" when sharing cardinality estimates with non-technical stakeholders.
- **Upstream connection:** Sketch structures (HyperLogLog, T-Digest, Count-Min) are foundational to streaming aggregation in Kafka/Flink pipelines; learn their error guarantees before building real-time dashboards.
- **Adjacent topic:** Bloom filters solve a related problem (set membership, not cardinality) with different memory–accuracy trade-offs; useful for deduplication and cache filtering.
- **Revisit:** Understand which aggregations your data warehouse supports as approximate (cardinality, percentiles, top-K) vs. exact; some systems fall back to exact if the sketch size exceeds thresholds.
- **Interview angle:** Be ready to justify approximate vs. exact: "For this dashboard, 1% error on 50M distinct users is acceptable and saves 300ms per query. For fraud detection, we need exact counts and accept the latency."
