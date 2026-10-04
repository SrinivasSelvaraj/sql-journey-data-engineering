---
date: 2026-10-04
phase: sql
topic: Approximate query processing and HyperLogLog cardinality
---

# Approximate query processing and HyperLogLog cardinality

*SQL for analytics and engineering*

## Concept

Approximate query processing trades precision for speed and memory efficiency when exact answers are impractical. **HyperLogLog** is a probabilistic data structure that estimates cardinality (distinct count) using logarithmic space—typically 12–16 KB regardless of dataset size—while maintaining ~2% error rates. Exact `COUNT(DISTINCT col)` requires materializing every unique value; HyperLogLog instead hashes values into a fixed-size register array, letting us estimate millions of distinct values without storing them.

This matters most in real-time dashboards, streaming aggregations, and data warehouse scans over billions of rows where `COUNT(DISTINCT user_id)` or `COUNT(DISTINCT session_id)` queries would otherwise require full table scans and sort operations. Without approximation, cardinality queries on high-cardinality dimensions block analytics pipelines; with HyperLogLog, you trade <2% accuracy for sub-second latency and predictable memory footprint.

Breaking without it: systems attempting exact distinct counts on 10B+ row tables without indexes hit memory exhaustion or timeout. Streaming systems cannot maintain exact state across distributed nodes without heavyweight shuffle operations. Approximate cardinality is not just optimization—it's the only feasible approach at scale for many real-time metrics.

## Practice

**Problem:** Your analytics team needs a dashboard showing daily estimated unique job locations and exact job counts. You must return results in under 2 seconds even as the table grows to 500M rows. Write a query using HyperLogLog approximation for locations and exact count for jobs.

```sql
SELECT 
  job_posted_date,
  COUNT(*) as total_jobs,
  APPROX_COUNT_DISTINCT(job_location) as approx_unique_locations
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY
GROUP BY job_posted_date
ORDER BY job_posted_date DESC;
```

**Alternative (Presto/Trino syntax):**
```sql
SELECT 
  job_posted_date,
  COUNT(*) as total_jobs,
  APPROX_PERCENTILE(salary_year_avg, 0.5) as median_salary,
  APPROX_COUNT_DISTINCT(job_location) as approx_unique_locations
FROM job_postings_fact
GROUP BY job_posted_date
ORDER BY job_posted_date DESC;
```

Both queries complete in milliseconds because `APPROX_COUNT_DISTINCT` uses HyperLogLog internally; exact `COUNT(DISTINCT job_location)` on the same dataset would require a full sort/hash aggregation and take 10–30+ seconds.

## Notes

- **Error vs. speed tradeoff:** HyperLogLog buys you ~99% accuracy (2% error) for queries that finish in 1% of the time; know your SLA before using approximation—never approximate cardinality for billing or compliance metrics.
- **No aggregation without approximation:** Most query engines (Postgres, MySQL, Snowflake, BigQuery) don't support exact `COUNT(DISTINCT)` over streaming data or distributed joins without materializing intermediate results; approximation is often the only option, not a luxury.
- **Adjacent topics:** Connects to bloom filters (set membership), t-digest (percentile approximation), and columnar index structures. HyperLogLog is one piece of a broader approximate computing toolkit.
- **Common mistakes:** Treating approximate results as exact in downstream joins, assuming all engines implement HyperLogLog equally (error rates vary), or using approximation on very small datasets where it adds overhead without benefit.
- **Revisit cardinality estimation cost models:** Understand when your engine uses exact vs. approximate under the hood; some databases switch strategies based on memory pressure or dataset size, and query plans may surprise you.
