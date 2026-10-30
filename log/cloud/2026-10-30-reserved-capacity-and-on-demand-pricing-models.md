---
date: 2026-10-30
phase: cloud
topic: Reserved capacity and on-demand pricing models
---

# Reserved capacity and on-demand pricing models

*Cloud platforms and storage*

## Concept

Reserved capacity and on-demand pricing represent two opposing cost models in cloud data platforms. **On-demand** charges per query (BigQuery), per compute-second (Databricks), or per GB scanned (Redshift Spectrum)—you pay only for what you use, but costs scale linearly with workload volume and can spike unpredictably. **Reserved capacity** commits you to a fixed monthly/annual spend for a pool of compute (BigQuery slots, Redshift nodes, Snowflake compute credits), lowering per-unit cost by 40–70% but locking in spend even during quiet periods.

This choice directly impacts query performance and cost predictability. On-demand systems may throttle or queue your query if cluster utilization is high; reserved systems guarantee consistent resource allocation but waste money if you under-utilize them. The break-even point depends on your query volume: if you run 500 TB scans monthly on BigQuery on-demand (~$2.50/TB = $1,250), 100 slots at $2,000/month becomes cheaper. Without understanding your actual consumption pattern, you either overpay for unused slots or face runaway bills and slow queries during peak hours.

## Practice

**Problem:** Your analytics team runs daily job posting reports (scanning the full `job_postings_fact` table) plus ad-hoc queries from 5 analysts. On-demand costs hit $8,000/month. The daily report also completes in 45 seconds during off-peak but 3+ minutes during business hours. Should you buy reserved capacity, and what's the minimum size?

```sql
-- Step 1: Estimate daily scan volume
SELECT 
  COUNT(*) as total_rows,
  ROUND(CAST(SUM(LENGTH(CAST(job_title_short AS STRING)) + 
                 LENGTH(CAST(job_location AS STRING))) AS FLOAT64) / 1e9, 2) as approx_gb
FROM job_postings_fact;

-- Step 2: Calculate monthly query volume (example: 1 daily report + 50 ad-hoc queries)
-- If daily report scans 50 GB and ad-hoc queries average 10 GB each:
-- Monthly: (50 GB * 30 days) + (50 queries * 10 GB) = 2,000 GB = ~$5/month on-demand
-- (Your actual $8k suggests either larger scans or more queries—audit query logs)

-- Step 3: Check if reserved capacity breaks even
-- BigQuery: 100 slots = $2,000/month, processes ~2,500 GB/month (25 GB/slot/day at 4 hour/day utilization)
-- If consuming 2,000 GB/month: break-even ≈ 80 slots (~$1,600/month)

-- Step 4: Reserve 100 slots for headroom and peak demand buffering
-- Expected savings: $8,000 - $2,000 = $6,000/month
```

## Notes

- **Audit before committing:** Export 30 days of query logs (cost, bytes_scanned, execution_time). If 80% of costs come from 5 queries, reserved capacity won't help—optimize those queries first.
- **Fractional utilization kills ROI:** Buying 100 slots but using only 40 slots' worth of capacity is waste. Right-size by percentile: if peak concurrent queries = 8 and each needs 15 slots, buy 120 slots, not 200.
- **Slot autoscaling and flex slots:** BigQuery now offers flex slots (hourly commitment, cheaper than monthly) and autoscaling—monitor these lower-friction alternatives before annual commitments.
- **Reserved capacity doesn't improve *per-query* latency directly:** Slots guarantee queue priority and allocation, but a poorly written scan of 500 GB still takes time. Pair capacity planning with query optimization (predicate pushdown, partitioning).
- **Revisit quarterly:** Workload patterns shift (new dashboards, seasonal hiring peaks). Reserve capacity that was optimal in Q2 may be wasteful by Q4; use cost anomaly alerts to catch misalignment.
