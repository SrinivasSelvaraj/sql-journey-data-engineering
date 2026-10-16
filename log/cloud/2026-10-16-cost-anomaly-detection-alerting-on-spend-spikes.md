---
date: 2026-10-16
phase: cloud
topic: Cost anomaly detection: alerting on spend spikes
---

# Cost anomaly detection: alerting on spend spikes

*Cloud platforms and storage*

## Concept

Cost anomaly detection identifies unexpected spikes in cloud spending—sudden jumps in compute, storage, or data transfer costs that deviate from baseline patterns. In data engineering, this matters because a single runaway query, inefficient join, or data scan can cost hundreds of dollars in minutes on platforms like BigQuery, Redshift, or Snowflake. Without anomaly detection, you discover the problem in next month's bill; with it, you catch and kill expensive jobs in real time.

The core mechanism uses statistical baselines (rolling averages, z-scores, or seasonal decomposition) to flag when daily or hourly spend exceeds a threshold—typically 2–3 standard deviations above the mean. Most cloud platforms offer built-in anomaly detection (AWS Budgets, GCP Cost Anomaly Detection, Azure Cost Management), but these trigger only after spend occurs. Pairing platform alerts with query-level instrumentation—logging bytes scanned, execution time, and estimated cost per job—lets you prevent anomalies rather than just react to them.

## Practice

**Problem:** You need to detect when a scheduled job that typically scans 500 GB and costs ~$2.50 suddenly starts scanning 10 TB (costing ~$50) due to a missing partition filter or cartesian join.

```sql
-- Instrument job runs with cost estimates
CREATE TABLE job_cost_log AS
SELECT
  job_id,
  job_title_short,
  job_posted_date,
  CURRENT_TIMESTAMP() AS run_timestamp,
  bytes_scanned,
  execution_seconds,
  -- BigQuery: $6.25 per TB scanned (on-demand)
  ROUND((bytes_scanned / 1e12) * 6.25, 2) AS estimated_cost_usd,
  -- Flag anomalies: > 3x the 7-day rolling median
  CASE 
    WHEN (bytes_scanned / 1e12) * 6.25 
         > 3 * MEDIAN(bytes_scanned) OVER (
             PARTITION BY job_id 
             ORDER BY job_posted_date 
             ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
           ) / 1e12 * 6.25
    THEN 'ANOMALY_DETECTED'
    ELSE 'NORMAL'
  END AS cost_status
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - 30
ORDER BY estimated_cost_usd DESC;

-- Alert on any anomaly
SELECT job_id, job_title_short, estimated_cost_usd, cost_status
FROM job_cost_log
WHERE cost_status = 'ANOMALY_DETECTED'
ORDER BY estimated_cost_usd DESC;
```

## Notes

- **Mistake:** Setting thresholds too tight (1.5σ) causes alert fatigue; too loose (4σ) misses real problems. Start at 2–3σ and tune weekly.
- **Mistake:** Ignoring baseline shifts—seasonal jobs (month-end reports) or known data quality fixes will temporarily spike legitimate spend; use time-windowed baselines.
- **Adjacent topic:** Query optimization (partition pruning, columnar projections, caching) is the upstream fix; cost anomaly detection is the safety net and diagnostic tool.
- **Revisit:** Integrate with incident response workflows—automate job cancellation or escalation, not just alerting.
- **Revisit:** Attribution—track costs by user, team, or application so spikes trigger accountability and faster root-cause analysis.
