---
date: 2026-08-24
phase: cloud
topic: Comparing BigQuery, Snowflake and Databricks for a use case
---

# Comparing BigQuery, Snowflake and Databricks for a use case

*Cloud platforms and storage*

## Concept

BigQuery, Snowflake, and Databricks serve the same use case (cloud data warehousing) but differ fundamentally in pricing model, compute separation, and query optimization strategy. BigQuery charges per byte scanned (on-demand) or via flat-rate slots; Snowflake charges per compute credit consumed; Databricks charges compute + storage separately with tight Delta Lake integration. Understanding these models matters because the *same query* can cost 10x more on one platform than another—not due to performance differences, but architectural choices. Query slowness has different root causes: BigQuery might scan unnecessary partitions, Snowflake might have insufficient warehouse credits allocated, and Databricks might have suboptimal Delta table statistics or cluster sizing.

Without understanding the cost driver for your platform, you'll optimize the wrong thing—adding indexes in BigQuery (which doesn't help scan costs), or clustering in Snowflake when you actually need a larger warehouse. The "why was the query slow" question requires different debugging: check `EXPLAIN` plans across platforms, monitor actual resource consumption (slots/credits/nodes), and correlate query complexity with cost multipliers specific to each engine.

## Practice

**Problem:** You run a job posting analysis query daily. Yesterday it took 45 seconds and cost $12 in BigQuery; today an identical query takes 3 seconds and costs $0.60. Your boss asks why the variance exists and whether you should switch to Snowflake's flat-rate model to avoid surprises.

```sql
-- First, understand *what* BigQuery scanned yesterday vs today
SELECT
  COUNT(DISTINCT job_id) as unique_jobs,
  AVG(salary_year_avg) as avg_salary,
  SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) as remote_jobs
FROM job_postings_fact
WHERE job_posted_date BETWEEN '2024-01-01' AND '2024-01-31'
  AND job_location IN ('United States', 'Remote');

-- Run with EXPLAIN to see partition pruning and bytes scanned:
EXPLAIN SELECT ... (same query above);

-- Check slot reservation usage:
SELECT
  slot_ms,
  total_bytes_billed,
  total_bytes_processed
FROM `project.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time BETWEEN TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
  AND CURRENT_TIMESTAMP()
ORDER BY creation_time DESC
LIMIT 10;

-- Decision: If job_posted_date is *not* your clustering key, 
-- add it; if scanned bytes vary wildly, verify partitioning exists.
```

## Notes

- **Snowflake's flat-rate model sounds safer but isn't**: $4/credit × 60 credits/hour = $240/hr minimum, often worse than BigQuery's per-query cost for ad-hoc analysis; only wins for predictable, sustained workloads.
- **Databricks' integration with Delta Lake is its edge case**: if you're already in the Lakehouse pattern (raw → bronze → silver → gold), Databricks optimization (Z-order, vacuum, stats) pays off; otherwise it's overengineered.
- **Partition pruning and clustering are *platform-specific magic***: BigQuery's partitioning on query column saves scan cost immediately; Snowflake requires explicit micro-partitions; Databricks needs Delta statistics refreshed.
- **"Slow" conflates latency with cost**: a 45-second query might be slow *and* expensive (full scan), slow *but* cheap (small result, high-latency I/O), or fast *and* expensive (many small scans). Separate the concerns.
- **Common mistake**: using `SELECT *` on wide tables or filtering *after* the full scan; always profile with `EXPLAIN ANALYZE` / `EXPLAIN (ANALYZE, FORMAT JSON)` before claiming platform X is slower than platform Y.
