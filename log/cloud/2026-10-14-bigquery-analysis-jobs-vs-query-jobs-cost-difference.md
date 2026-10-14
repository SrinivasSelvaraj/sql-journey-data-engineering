---
date: 2026-10-14
phase: cloud
topic: BigQuery analysis jobs vs query jobs: cost difference
---

# BigQuery analysis jobs vs query jobs: cost difference

*Cloud platforms and storage*

## Concept

BigQuery distinguishes between **analysis jobs** and **query jobs** primarily through their scope and billing impact. A query job executes SQL and scans table data, incurring costs based on bytes scanned (unless using flat-rate pricing). An analysis job, by contrast, refers to operations like `ANALYZE TABLE` statements that compute table statistics without scanning user data—these are typically free or have minimal cost. Understanding this distinction matters because misidentifying slow performance as a query problem when it's actually a missing statistics problem can lead to unnecessary optimization efforts.

The cost difference becomes critical at scale. A single poorly written query scanning 100 GB of uncompressed data costs roughly $0.50 (at standard on-demand rates), but running that query repeatedly without analyzing table structure wastes money across multiple executions. Without explicit analysis jobs, BigQuery's query planner may make poor cardinality estimates, leading to inefficient execution plans and slower (but still billable) queries. Conversely, a one-time `ANALYZE TABLE` statement costs nothing and can dramatically improve subsequent query performance by giving the optimizer better statistics.

## Practice

**Problem:** You notice that a daily report querying `job_postings_fact` is taking 45 seconds, scanning 2.8 GB each time. The query filters on `job_location` and `job_posted_date`, but the planner seems to be making poor decisions about join order when combined with a secondary table.

**Solution:**

```sql
-- First, analyze the table to generate column statistics
ANALYZE TABLE project.dataset.job_postings_fact COMPUTE STATISTICS;

-- Then run your optimized query with better planner estimates
SELECT 
  job_title_short,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary
FROM project.dataset.job_postings_fact
WHERE job_posted_date >= CURRENT_DATE() - 30
  AND job_location IN ('New York, NY', 'San Francisco, CA')
GROUP BY job_title_short
ORDER BY posting_count DESC;
```

The `ANALYZE TABLE` statement generates histograms and cardinality estimates for all columns, allowing the query optimizer to choose better execution plans for subsequent queries without increasing data scan costs.

## Notes

- **Billing trap:** Both query jobs and analysis jobs appear in your BigQuery audit logs, but only query jobs consume query slots and incur scanned-bytes costs. Don't confuse "free analysis" with "cheap query"—the analysis itself is free, but the query that follows still charges normally.

- **Stale statistics:** BigQuery automatically refreshes table statistics roughly every 7 days for high-activity tables, but manually running `ANALYZE TABLE` before critical reporting jobs guarantees fresh estimates and predictable performance.

- **Materialized views & snapshots:** Related cost concept—materialized views pre-compute and store results (you pay for storage), while query jobs scan live tables. Analysis jobs help optimize both, but they solve different problems.

- **Partitioning + analysis:** Partition pruning happens at the physical level (before statistics), but column statistics from analysis jobs help the planner choose which partitions to scan. Always analyze after major schema changes.

- **Worth revisiting:** Difference between `COMPUTE STATISTICS` (full table) and `COMPUTE INCREMENTAL STATISTICS` (delta since last run); when to use approximate functions (`APPROX_QUANTILES`) to avoid full scans during exploratory analysis.
