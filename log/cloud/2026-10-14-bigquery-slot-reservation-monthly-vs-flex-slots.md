---
date: 2026-10-14
phase: cloud
topic: BigQuery slot reservation: monthly vs flex slots
---

# BigQuery slot reservation: monthly vs flex slots

*Cloud platforms and storage*

## Concept

BigQuery offers two slot reservation models that directly impact both cost predictability and query performance. **Monthly slots** commit you to a fixed number of 100-slot increments for 30 days at ~$2,000/slot/month, providing baseline capacity that queries can always access; **flex slots** charge per-second (~$0.04/slot/second) with no commitment and scale on-demand, ideal for variable workloads but costlier at peak usage. The key trade-off: monthly slots guarantee concurrency and predictable spend if you have sustained volume, while flex slots suit sporadic or bursty analytics without idle-slot waste.

Query slowness without adequate slots manifests as queueing—BigQuery will defer your query if no slots are available, even if the query logic is efficient. This differs from performance bottlenecks in the query plan itself. If you run many concurrent heavy aggregations and only have 100 monthly slots reserved, each query waits in line; scaling to 200 slots or switching to flex would eliminate the queue delay but flex's per-second cost becomes expensive if you run 10 concurrent queries for hours.

Understanding your actual slot consumption requires monitoring `INFORMATION_SCHEMA.JOBS_BY_PROJECT` and examining query execution timeline metrics in the UI (look for "Slot milliseconds" in job details). A query using 50 slots for 10 seconds consumes 500 slot-seconds; monthly slots amortize this across the month, while flex slots charge directly per second used.

## Practice

**Problem:** Your analytics team runs daily reporting queries between 9–11 AM UTC, consuming ~150 slots concurrently for 2 hours, but queries on `job_postings_fact` are timing out or queuing heavily. You need to determine whether to reserve monthly slots or use flex, assuming 22 working days/month.

```sql
-- Estimate daily slot-second consumption from historical jobs
SELECT
  DATE(creation_time) AS query_date,
  SUM(total_slot_ms) / 1000 AS total_slot_seconds,
  COUNTIF(state = 'DONE') AS completed_queries,
  MAX(CAST(total_slot_ms / 1000 AS INT64)) AS peak_query_slot_seconds
FROM `project.region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE DATE(creation_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
  AND user_defined_functions IS NULL  -- exclude UDF overhead noise
GROUP BY query_date
ORDER BY query_date DESC;

-- Calculate cost comparison
-- Assume 150 concurrent slots for 2 hours = 150 * 7200 = 1,080,000 slot-seconds/day
-- Monthly: 200 slots * $2000 = $4000/month
-- Flex: 1,080,000 * 22 days * $0.04 / 3600 = ~$264/month
-- → Flex is cheaper unless concurrent demand grows or you need guaranteed capacity
```

## Notes

- **Slot commitment lock-in:** Monthly slots are fixed for 30 days; you cannot downgrade mid-month, so only commit if you have baseline traffic that justifies it over a 3–6 month horizon.
- **Flex slots are not cheaper by default:** Many teams assume flex is always cheaper because it's pay-as-you-go, but at sustained 150+ concurrent slots, monthly becomes cost-optimal quickly.
- **Slot sharing across projects:** If you reserve slots at the organization or folder level, all projects draw from the same pool; this requires careful quota management and can hide cost allocation to individual teams.
- **Query queuing vs. slow query:** A query showing 60 seconds total time might spend 50 seconds in queue (slot unavailable) and 10 seconds executing; this is invisible in query duration alone—check the job timeline in the UI or query `INFORMATION_SCHEMA.JOBS_BY_PROJECT.total_slot_ms`.
- **Adjacent: commitment discounts & autoscaling:** Beyond slots, BigQuery offers annual/multi-year commitments for further discounts (25% off monthly); some teams layer autoscaling policies on top of monthly slots to burst into flex during spikes.
