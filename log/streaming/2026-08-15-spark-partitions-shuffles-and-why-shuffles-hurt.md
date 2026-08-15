---
date: 2026-08-15
phase: streaming
topic: Spark: partitions, shuffles and why shuffles hurt
---

# Spark: partitions, shuffles and why shuffles hurt

*Streaming and distributed processing*

## Concept

Partitions are the fundamental unit of parallelism in Spark. Data is split across partitions so that executors can process chunks independently and in parallel. Without enough partitions, you underutilize your cluster; with too many, you create scheduling overhead. The partition key matters: if your data naturally groups by user_id but you partition by date, related records scatter across the cluster.

Shuffles occur when Spark must redistribute data across partitions—typically during `groupBy`, `join`, `distinct`, or `repartition` operations. A shuffle writes data to disk on source executors, then reads it from disk on destination executors. This is expensive: disk I/O is slow, network transfer is slow, and it forces a barrier (all tasks must complete before the next stage begins). In streaming workloads, shuffles create latency spikes and can cause backpressure if data arrives faster than shuffled data can drain.

Shuffles hurt most when you shuffle wide datasets repeatedly or when your partition strategy doesn't align with your access patterns. For example, aggregating by job_location when data arrives partitioned by job_posted_date forces a full shuffle on every micro-batch. Minimize shuffles by: choosing the right initial partition count (2–4× executor count), partitioning by columns you frequently filter or group on, and coalescing small partitions before shuffling.

## Practice

**Problem:** You have a streaming job that ingests job postings and needs to compute the average salary by job_location every minute. Data arrives unordered and partitioned by ingestion timestamp. Your current query shuffles the entire dataset on every micro-batch, causing memory pressure and 8–10 second latency spikes.

```sql
-- Current (bad): shuffles all data every batch
SELECT 
  job_location,
  AVG(salary_year_avg) AS avg_salary,
  COUNT(*) AS posting_count
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 30 DAYS
GROUP BY job_location;

-- Solution: pre-partition and aggregate before the final shuffle
-- 1. Repartition by job_location once (one-time cost)
-- 2. Use a window function or incremental aggregation within each partition
-- 3. Only shuffle the final small aggregated results

WITH ranked_postings AS (
  SELECT 
    job_location,
    salary_year_avg,
    ROW_NUMBER() OVER (PARTITION BY job_location ORDER BY job_posted_date DESC) AS recency_rank
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL 30 DAYS
)
SELECT 
  job_location,
  AVG(salary_year_avg) AS avg_salary,
  COUNT(*) AS posting_count
FROM ranked_postings
WHERE recency_rank <= 1000  -- limit per location to reduce shuffle volume
GROUP BY job_location;
```

## Notes

- **Partition count rule of thumb:** aim for 2–4 partitions per executor core; too few → underutilization, too many → scheduling overhead and tiny files.
- **Shuffle vs. broadcast:** if one table is small (<200 MB), broadcast join it instead of shuffling both tables; eliminates the shuffle entirely.
- **Streaming gotcha:** micro-batch processing can hide shuffle costs; profile end-to-end latency, not just compute time. Shuffles include I/O wait.
- **Partition pruning matters:** if you filter by job_posted_date *before* grouping by job_location, Spark can skip entire partitions if they're organized by date; this reduces shuffle volume.
- **Revisit:** adaptive query execution (AQE) can reoptimize shuffles mid-query; understand when it helps and when manual hints (like bucketing by job_location) are better for predictable streaming jobs.
