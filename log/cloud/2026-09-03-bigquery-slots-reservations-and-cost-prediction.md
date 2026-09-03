---
date: 2026-09-03
phase: cloud
topic: BigQuery: slots, reservations and cost prediction
---

# BigQuery: slots, reservations and cost prediction

*Cloud platforms and storage*

## Concept

BigQuery charges for two things: data scanned (analysis pricing) and compute resources (slots). By default, you pay per query based on bytes scanned; slots are a reserved commitment model where you buy fixed compute capacity by the month or year, then run unlimited queries within that capacity. Slots matter when your workload is predictable and substantial (>$2–3k/month in on-demand costs), or when you need to guarantee query performance for production dashboards and reports that can't afford to queue behind other users' jobs.

Without understanding slots and reservations, you either overpay for bursty ad-hoc queries or underprovision for production workloads and watch queries throttle during peak hours. Reservations let you isolate teams or projects so that one department's large ETL job doesn't starve another team's interactive queries. Cost becomes unpredictable if you don't reserve capacity and your query volume spikes; conversely, you waste money if you over-reserve.

The key insight: slots control *concurrency and speed*, not bytes scanned. A 100-slot reservation gives you 100 parallel execution threads; a query either completes fast within your slots or queues and then runs when slots free up. Monitoring slot utilization tells you whether you're sized correctly.

## Practice

**Problem:** Your team runs hourly aggregations on `job_postings_fact` that scan 5 GB each, plus ad-hoc analyst queries. You're spending $800/month on analysis fees and queries are taking 45–90 seconds. Predict whether 100 slots would be cost-effective and how to measure it.

```sql
-- Step 1: Measure current scan volume and query count over past 7 days
SELECT
  DATE(creation_time) as query_date,
  COUNT(*) as query_count,
  ROUND(SUM(total_bytes_processed) / POW(10, 9), 2) as total_gb_scanned,
  ROUND(AVG(total_slot_ms) / 1000, 1) as avg_slot_seconds
FROM `project.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND job_type = 'QUERY'
  AND state = 'DONE'
GROUP BY query_date
ORDER BY query_date DESC;

-- Step 2: Project monthly cost and slot utilization
-- On-demand: $6.25 per TB scanned
-- 100 slots: $2,400/month (annual commitment: $24,000)
-- Break-even if you scan >384 TB/month (2400 / 6.25)

-- Step 3: Check if reserved slots would have helped (estimate from slot_ms)
SELECT
  PERCENTILE_CONT(total_slot_ms / 1000, 0.5) OVER () as p50_slot_seconds,
  PERCENTILE_CONT(total_slot_ms / 1000, 0.95) OVER () as p95_slot_seconds,
  MAX(total_slot_ms / 1000) as max_slot_seconds,
  COUNT(*) as total_queries
FROM `project.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND job_type = 'QUERY'
  AND state = 'DONE';
```

## Notes

- **Common mistake:** Confusing slots with memory per query. Slots are concurrency units; you still need to optimize your SQL to avoid shuffles and large JOINs on unpartitioned tables.
- **Break-even math:** Slots only pay off if your monthly on-demand spend exceeds the slot cost. Use `INFORMATION_SCHEMA.JOBS_BY_PROJECT` to audit `total_bytes_processed` over 30 days; multiply by $6.25/TB.
- **Measurement gap:** BigQuery doesn't directly show "queries queued" in standard logs; high slot utilization + longer query times suggest contention. Use Cloud Monitoring dashboards to track `bigquery.googleapis.com/slots/total_allocated` vs. `total_used`.
- **Reservation isolation:** Create separate reservations for ETL (batch, predictable) and analytics (interactive, bursty) workloads; assign projects/datasets to each via assignment rules to prevent one job from starving another.
- **Adjacent topic:** Query cost optimization (clustering, partitioning, approximate aggregates) runs *parallel* to slot planning; slots don't excuse expensive queries, they just make them run faster.
