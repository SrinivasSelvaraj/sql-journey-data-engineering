---
date: 2026-09-25
phase: cloud
topic: Memory allocation and pricing non-linearity
---

# Memory allocation and pricing non-linearity

*Cloud platforms and storage*

## Concept

Memory allocation in cloud data warehouses (Snowflake, BigQuery, Redshift) is often non-linear: adding 2× workers or compute doesn't always yield 2× speed or cost savings. This happens because query execution has fixed overhead (parsing, metadata lookup, result serialization), network shuffling during joins creates bottlenecks, and skewed data distribution means some nodes finish while others still process. Understanding this prevents you from oversizing clusters (wasting money) or undersizing them (queries timeout or spill to disk, becoming exponentially slower).

The cost implication is critical: you may pay for idle compute while waiting on a single slow shuffle operation, or pay for expensive disk spilling when aggregating a billion rows with only 4GB allocated per node. Pricing isn't "per row processed"—it's per compute unit provisioned *for the duration of execution*, whether fully utilized or not. A query that runs 10 minutes on 8 cores costs more than one running 2 minutes on 16 cores, even if both process the same data, because you're renting the resource for longer.

## Practice

**Problem:** You're running a daily job that joins `job_postings_fact` to a large candidate pool table on `job_location`. Some locations (e.g., "Remote") represent 40% of all rows, causing data skew. The query times out on small cluster size, but doubling the cluster only reduces runtime by 20% instead of the expected 50%. You need to identify if it's a memory/shuffle bottleneck.

```sql
-- Diagnose skew and force broadcast join for small dimension
SELECT job_location, COUNT(*) as posting_count
FROM job_postings_fact
GROUP BY job_location
ORDER BY posting_count DESC;

-- Solution: use broadcast join hint to avoid shuffle on skewed column
SELECT /*+ BROADCAST(locations) */ 
  j.job_id, 
  j.job_title_short, 
  j.salary_year_avg,
  l.location_region
FROM job_postings_fact j
INNER JOIN location_dim l
  ON j.job_location = l.location_name
WHERE j.job_posted_date >= CURRENT_DATE - 30;
-- Alternatively, pre-aggregate on skewed key before join to reduce rows early
```

## Notes

- **Skew detection first:** Always `GROUP BY` the join key and check cardinality distribution before tuning cluster size. 80/20 rule skew often defeats parallelism.
- **Spilling costs hidden:** When a node runs out of allocated memory, it writes to disk (Snowflake's `SPILL_TO_DISK` metric). This is 50–100× slower than RAM; monitor query profile, not just wall-clock time.
- **Query profiling is non-negotiable:** Cloud platforms provide execution plans showing which stage consumed 95% of time (shuffle, aggregate, scan). Use Snowflake's Query Profile, BigQuery's Explain Plan, or Redshift's EXPLAIN ANALYZE before buying more compute.
- **Fixed overhead tax:** Simple queries (count, filter) benefit less from scaling than complex ones (multi-join, window functions) because setup cost is proportionally larger. A 1-second overhead on a 2-second query is 50% waste; on a 100-second query it's 1%.
- **Connect to partitioning & indexing:** Memory pressure is often a symptom of poor table design. Partition `job_postings_fact` by `job_posted_date` to prune full scans; cluster by `job_location` to reduce shuffle volume on common joins.
