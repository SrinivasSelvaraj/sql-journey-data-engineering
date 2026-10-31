---
date: 2026-10-31
phase: cloud
topic: Budget alerts and cost anomaly detection
---

# Budget alerts and cost anomaly detection

*Cloud platforms and storage*

## Concept

Budget alerts and cost anomaly detection are mechanisms to monitor cloud spending in real time and flag unexpected increases before they become costly problems. In platforms like AWS, GCP, and Azure, query costs scale with data scanned, compute time, and storage—not just execution count. Without visibility, a single poorly optimized query (e.g., a full table scan with no partition pruning, or a runaway loop writing intermediate results) can cost hundreds or thousands of dollars in hours. Anomaly detection works by establishing a baseline of normal spending patterns, then alerting when actual spend deviates significantly—catching mistakes before they compound.

Cost visibility also forces discipline: you learn which queries are expensive, which transformations waste compute, and which storage decisions (compression, partitioning, archival) matter. Many engineers optimize for speed first and never see the bill; cost alerts close that feedback loop and make performance and cost inseparable concerns.

## Practice

**Problem:** You notice your cloud bill spiked 40% last month, but you don't know which job caused it. You need to identify the most expensive queries and set up an alert to catch similar patterns early.

```sql
-- 1. Calculate query costs (GCP BigQuery example; adjust for your platform)
WITH query_costs AS (
  SELECT
    creation_time,
    user_email,
    query,
    ROUND(bytes_billed / POW(10, 12), 2) AS tb_scanned,
    ROUND((bytes_billed / POW(10, 12)) * 6.25, 2) AS estimated_cost_usd,
    execution_time_ms
  FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
  WHERE creation_time >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
    AND state = 'DONE'
)
-- 2. Identify anomalies (queries costing >3x the 30-day median)
SELECT
  creation_time,
  user_email,
  SUBSTR(query, 1, 100) AS query_preview,
  tb_scanned,
  estimated_cost_usd,
  execution_time_ms,
  ROUND(estimated_cost_usd / (SELECT AVG(estimated_cost_usd) FROM query_costs), 2) AS cost_ratio_vs_avg
FROM query_costs
WHERE estimated_cost_usd > (SELECT PERCENTILE_CONT(estimated_cost_usd, 0.9) FROM query_costs)
ORDER BY estimated_cost_usd DESC
LIMIT 20;
```

Set up a **scheduled alert** (e.g., daily Airflow task or cloud native scheduler) that sends Slack/email if any query exceeds your threshold or if daily spend > historical_avg × 1.5.

## Notes

- **Partition and cluster your fact tables** on date and common filters (job_location, job_work_from_home) to reduce bytes scanned; most cloud bill surprises come from full-table scans that could be pruned.
- **Reserved capacity vs. on-demand**: if you have predictable baseline load, reserved slots/commitments are 30–50% cheaper than on-demand, but require forecasting.
- **Watch for data duplication**: temporary tables, intermediate results, and backups can silently inflate storage costs; implement retention policies and monitor table row counts.
- **Cost attribution**: tag queries with team/project/dataset to distribute costs fairly and identify which business unit is driving the spike.
- **Adjacent topics**: query execution plans (EXPLAIN), storage optimization (compression, columnar format), and multi-region replication all have cost multipliers—learn them together.
