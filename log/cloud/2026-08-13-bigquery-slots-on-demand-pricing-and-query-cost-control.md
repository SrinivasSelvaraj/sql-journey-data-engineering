---
date: 2026-08-13
phase: cloud
topic: BigQuery: slots, on-demand pricing and query cost control
---

# BigQuery: slots, on-demand pricing and query cost control

*Cloud platforms and storage*

## Concept

BigQuery charges based on data scanned (on-demand) or committed capacity (slots). On-demand pricing is simple—pay per TB scanned—but unpredictable and expensive at scale. Slots provide fixed monthly or annual commitments (minimum 100 slots; each slot = 100 queries/second compute capacity) and decouple cost from query volume. This matters because a single poorly written query scanning 100 TB can cost hundreds of dollars, while the same analysis optimized to scan 1 TB costs a fraction of that. Without understanding slot utilization and query patterns, you either overpay for on-demand or underutilize reserved capacity. Query cost control means: partition by date, cluster on filter columns, select only needed fields, and use `APPROX_*` functions when precision isn't critical.

## Practice

**Problem:** You're analyzing job postings and running this query frequently on the `job_postings_fact` table (500M rows, 50 GB uncompressed). It scans the entire table every time, costing $0.25 per run. Optimize it to scan only the data needed.

```sql
-- ❌ BEFORE: Full table scan, no pruning
SELECT job_title_short, AVG(salary_year_avg)
FROM job_postings_fact
WHERE job_work_from_home = TRUE
GROUP BY job_title_short;

-- ✅ AFTER: Partition + cluster + filter on date
-- (Assumes table is partitioned by job_posted_date, clustered by job_work_from_home)
SELECT job_title_short, AVG(salary_year_avg)
FROM job_postings_fact
WHERE job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  AND job_work_from_home = TRUE
GROUP BY job_title_short;

-- Cost reduction: from ~25 GB scanned to ~2 GB (90-day window)
```

## Notes

- **Partition pruning is non-negotiable:** Always filter on the partition column (`job_posted_date`). BigQuery skips entire partitions before scanning. Without it, you pay for data you didn't ask for.
- **Clustering amplifies partitioning:** If you filter frequently on `job_work_from_home` or `job_location`, cluster on those columns. Clustered data is co-located on disk, reducing I/O per query.
- **SELECT only columns you need:** Selecting `*` or unused fields increases bytes scanned. Be explicit: `SELECT job_title_short, salary_year_avg` not `SELECT *`.
- **Slots vs. on-demand trade-off:** On-demand suits ad-hoc/bursty queries; slots suit predictable workloads (dashboards, ETL). Hybrid strategies exist: use slots for known dashboards, on-demand for exploration.
- **Adjacent: monitor with `INFORMATION_SCHEMA.JOBS_BY_*`** to audit which queries consume most slots/bytes. Use `--dry_run` flag (`bq query --dry_run`) to estimate cost before running.
