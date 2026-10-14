---
date: 2026-10-14
phase: cloud
topic: BigQuery clustering and partitioning: query pruning
---

# BigQuery clustering and partitioning: query pruning

*Cloud platforms and storage*

## Concept

Clustering and partitioning enable **query pruning**—BigQuery's ability to skip entire blocks of data without reading them, reducing bytes scanned and cost. Partitioning divides a table by a single column (typically DATE or TIMESTAMP) into separate physical segments; clustering organizes rows within partitions by 2–4 columns (e.g., job_location, job_title_short). When you filter on a partitioned or clustered column, BigQuery's metadata layer identifies which segments contain matching data and ignores the rest.

Without pruning, every query reads the entire table regardless of your WHERE clause. With a 10 GB table partitioned by date, a query filtering for last week might read only 100 MB—a 100× cost reduction. This matters immediately: slots cost per query execution, on-demand billing charges per byte scanned, and query latency increases with data volume.

Pruning breaks silently if you filter on non-partitioned/non-clustered columns, use expressions that prevent metadata evaluation (e.g., `WHERE DATE(job_posted_date) = CURRENT_DATE()` instead of `WHERE job_posted_date = CURRENT_DATE()`), or partition/cluster on columns with poor cardinality (e.g., job_work_from_home BOOLEAN gives only 2 segments).

## Practice

**Problem:** Your analytics team runs daily reports filtering `job_postings_fact` by posting date (last 30 days) and job location (New York, San Francisco, Austin). The unoptimized table is 500 GB. Current queries scan 50+ GB daily, costing $250/day on on-demand pricing. Design a partitioning and clustering strategy to reduce scan volume.

```sql
-- Create partitioned and clustered table
CREATE OR REPLACE TABLE `project.dataset.job_postings_fact`
PARTITION BY DATE(job_posted_date)
CLUSTER BY job_location, job_title_short
AS
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM `project.dataset.job_postings_raw`;

-- Query that benefits from pruning
-- Scans only relevant date partitions + clusters matching locations
SELECT
  job_location,
  job_title_short,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary
FROM `project.dataset.job_postings_fact`
WHERE job_posted_date >= CURRENT_DATE() - 30  -- Partition pruning
  AND job_location IN ('New York', 'San Francisco', 'Austin')  -- Cluster pruning
GROUP BY job_location, job_title_short;
```

Expected result: ~5 GB scanned (10% of original), reducing daily cost to ~$25.

## Notes

- **Partition elimination is strict; clustering is probabilistic.** Partitioning guarantees metadata skipping; clustering helps *if* rows cluster well, but doesn't guarantee segment elimination. Check `BYTES_SCANNED` in query stats.
- **Avoid expression-wrapped partition filters.** `WHERE DATE(job_posted_date) = '2024-01-15'` prevents pruning; use `WHERE job_posted_date = '2024-01-15'` instead. BigQuery cannot evaluate expressions before reading.
- **Over-clustering wastes space.** Clustering on 5+ columns increases storage (denser sorts) without proportional benefit. Stick to 2–4 high-cardinality, frequently-filtered columns.
- **Monitor partition skew.** If 90% of data lands in one partition (e.g., all recent jobs), partitioning doesn't help. Check table stats via `SELECT * FROM project.dataset.__PARTITIONS_SUMMARY__`.
- **Relates to:** materialized views (pre-aggregate pruned data), table expiration (auto-delete old partitions), and cost estimation (use `--dry_run` flag in CLI to preview bytes without execution).
