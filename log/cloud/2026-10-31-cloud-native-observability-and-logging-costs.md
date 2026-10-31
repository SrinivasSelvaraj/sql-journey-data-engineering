---
date: 2026-10-31
phase: cloud
topic: Cloud-native observability and logging costs
---

# Cloud-native observability and logging costs

*Cloud platforms and storage*

## Concept

Cloud-native observability means instrumenting your data pipelines to track costs, performance, and resource usage in real time—not after the bill arrives. Without visibility into query execution, storage scanning, and data transfer, you pay for inefficiency without knowing where the waste occurs. A single unoptimized join across terabytes in BigQuery or Athena can cost hundreds of dollars in a few seconds; a poorly partitioned table forces full scans instead of pruning.

Observability becomes critical at scale. During development, queries run fast on small datasets. In production, that same query might scan 50GB unnecessarily because it lacks partition pruning or pushes filtering to the wrong layer. Cloud data warehouses charge by data scanned, not by time or compute—this inverts traditional optimization: you optimize *what you scan*, not just how fast you scan it.

Without logging query execution details (duration, bytes scanned, bytes returned, slot usage), you cannot distinguish between a slow query that's I/O bound versus one that's compute bound. You cannot justify infrastructure investments or identify which teams are responsible for cost spikes. Observability is the feedback loop that turns "our cloud bill is high" into "partitioning by job_posted_date and filtering before the join saves 40GB per query."

## Practice

**Problem:** Your analytics team runs a daily report on job postings. The query joins job_postings_fact to a large salary_benchmarks table, filters for remote work, and groups by job title. It runs hourly and costs $30–50 per execution. You suspect it's scanning data unnecessarily.

```sql
-- Instrument the query with partition pruning and cost-aware filtering
-- BigQuery example with query execution insights

DECLARE scan_bytes_budget INT64 DEFAULT 10737418240;  -- 10 GB budget

EXPLAIN ANALYZE
SELECT
  job_title_short,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary,
  COUNT(*) AS postings_count
FROM
  project.dataset.job_postings_fact
WHERE
  job_posted_date >= CURRENT_DATE() - 30  -- Partition pruning: critical
  AND job_work_from_home = TRUE
GROUP BY
  job_title_short
ORDER BY
  postings_count DESC
LIMIT 100;

-- ACTION: Check query plan output for:
-- - Bytes scanned vs. table total size (should be << 10GB)
-- - Filter pushdown happens before GROUP BY
-- - Partition elimination count (should filter to 30 days, not full table)
-- If bytes scanned > budget, add materialized view or clustering
```

## Notes

- **Partition pruning is non-negotiable:** Always filter on the partition key early (date, region, customer_id). Cloud systems only *avoid* scanning partitions you explicitly exclude; lazy filters cost you full-table scans.
- **Logs are data:** Query logs themselves become observability data. Set up alerts on scan/cost metrics (e.g., "queries scanning >100GB") so you catch regressions before the bill does.
- **Adjacent: query result caching** — Idempotent queries repeated within hours should hit cache, not re-scan. Track cache hit rates; low rates signal repeated expensive work.
- **Common mistake:** Filtering *after* joins. Always filter source tables before joining; filtering joined results still charged you for the full scan.
- **Revisit cost modeling:** Understand your platform's pricing (per-TB-scanned vs. per-slot vs. per-compute-second). Optimization strategy differs: BigQuery favors scanning less; Redshift favors slot efficiency.
