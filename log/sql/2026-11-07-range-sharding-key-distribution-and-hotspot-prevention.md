---
date: 2026-11-07
phase: sql
topic: Range sharding: key distribution and hotspot prevention
---

# Range sharding: key distribution and hotspot prevention

*SQL for analytics and engineering*

## Concept

Range sharding divides data into contiguous ranges of a shard key (e.g., date ranges, numeric IDs) and distributes each range to different physical nodes or partitions. Without thoughtful key selection, a single range can receive disproportionate write or query traffic—a **hotspot**—causing that shard to become a bottleneck while others remain underutilized. This is especially critical in high-velocity analytics pipelines where time-series data (job postings by date, events by timestamp) naturally clusters.

The core tension: range sharding is simple to reason about and query (range filters map cleanly to shard predicates), but poor cardinality distribution or skewed domain values create hotspots. For example, sharding `job_postings_fact` by `job_posted_date` with monthly ranges works well if posting volume is steady; but if 80% of posts arrive on Mondays, Monday's shard overheats. Hotspots degrade both write throughput and query latency because queries that hit the hot shard wait behind saturated I/O or lock contention.

Prevention requires analyzing the distribution of your shard key upfront—percentiles, skew, growth rate—and either choosing a composite key (date + geography) or dynamically adjusting range boundaries. In SQL analytics, you can detect hotspots by counting rows per range and comparing against expected distribution; then re-shard or rebalance.

## Practice

**Problem:** You have `job_postings_fact` with 5M rows posted over the past 2 years. You plan to shard by `job_posted_date` using monthly ranges. Write a query to identify which months are hotspots (contain >15% of total volume) and would cause uneven load distribution.

```sql
WITH monthly_counts AS (
  SELECT
    DATE_TRUNC('month', job_posted_date) AS month_start,
    COUNT(*) AS postings_in_month
  FROM job_postings_fact
  GROUP BY DATE_TRUNC('month', job_posted_date)
),
totals AS (
  SELECT SUM(postings_in_month) AS total_postings FROM monthly_counts
)
SELECT
  m.month_start,
  m.postings_in_month,
  ROUND(100.0 * m.postings_in_month / t.total_postings, 2) AS pct_of_total,
  CASE
    WHEN 100.0 * m.postings_in_month / t.total_postings > 15 THEN 'HOTSPOT'
    ELSE 'OK'
  END AS shard_health
FROM monthly_counts m, totals t
ORDER BY m.postings_in_month DESC;
```

This reveals which months exceed the 15% threshold. If January has 25%, you'd either split January into two shards, switch to a composite key (`DATE_TRUNC('month', job_posted_date), job_location`), or use dynamic range adjustment.

## Notes

- **Composite keys reduce hotspots:** Shard by `(job_posted_date, job_location)` to spread load geographically within each month; trade-off is slightly more complex query routing and range predicates.
- **Percentile analysis is essential:** Before sharding, compute p50, p95, p99 of key cardinality; if p99 is 10× p50, single ranges will be uneven—consider bucketing or hash-range hybrids.
- **Adjacent: hash sharding vs. range sharding.** Hash sharding distributes uniformly but makes range queries (e.g., "all jobs posted in Q1") expensive; range sharding inverts this trade-off.
- **Hotspot rebalancing is expensive:** Reshuffling data across shards has high operational cost; design upfront with growth and seasonality in mind (summer hiring spikes for certain roles).
- **Monitor shard metrics in production:** Query latency, disk I/O, and row counts per shard should be tracked continuously; alert when any shard drifts >20% above the mean.
