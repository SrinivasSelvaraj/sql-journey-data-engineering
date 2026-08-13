---
date: 2026-08-13
phase: cloud
topic: Databricks and the lakehouse model
---

# Databricks and the lakehouse model

*Cloud platforms and storage*

## Concept

Databricks is a unified analytics platform built on Apache Spark that implements the lakehouse model—combining the cost efficiency and flexibility of data lakes with the reliability and performance of data warehouses. Unlike traditional data warehouses that store only structured, pre-processed data, a lakehouse stores raw and refined data in open formats (Parquet, Delta) on cheap object storage (S3, ADLS), while adding ACID transactions, schema enforcement, and indexing through Delta Lake. This matters because you can ingest petabyte-scale raw data without expensive ETL upfront, query it directly with SQL, and pay only for compute when you run queries—not for idle storage like in Redshift or Snowflake.

Breaks without it: organizations often run into slow queries because they're querying unpartitioned raw Parquet files across thousands of objects in S3, or they lack proper indexing and statistics, causing full table scans. Databricks addresses this through Delta Lake's Z-order clustering, statistics collection, and file pruning. Also breaks is cost visibility—without understanding Databricks' per-DBU (Databricks Unit) billing model and how many cores your query uses, you can't reason about why a seemingly simple query costs $50.

## Practice

**Problem:** You have 2 years of job posting data (50M rows). Queries filtering by `job_posted_date` are slow, and the dashboard that filters by `job_work_from_home = true` takes 45 seconds. You need to optimize for speed and understand the storage cost.

```sql
-- Convert raw table to Delta format with partitioning and optimization
CREATE TABLE job_postings_fact_optimized
USING DELTA
PARTITIONED BY (job_posted_date)
AS SELECT * FROM job_postings_fact;

-- Cluster by frequently filtered columns for Z-order pruning
ALTER TABLE job_postings_fact_optimized
SET TBLPROPERTIES ('delta.dataSkippingNumIndexedCols' = 10);

-- Run OPTIMIZE to compact files and gather statistics
OPTIMIZE job_postings_fact_optimized
ZORDER BY (job_work_from_home, job_location);

-- Now queries filter efficiently
SELECT job_title_short, salary_year_avg
FROM job_postings_fact_optimized
WHERE job_posted_date >= '2023-01-01' 
  AND job_work_from_home = true;
```

## Notes

- **DBU billing trap:** Databricks charges per DBU-hour (roughly $0.15–$1.50/DBU depending on workload type). A 4-core cluster running 1 hour = 4 DBUs. Always monitor query execution plans in Spark UI to catch shuffle operations and skew.
- **Partitioning matters most:** Partition by the column you filter on most (date, region). Over-partitioning (100k+ partitions) causes metadata overhead; under-partitioning defeats file pruning.
- **Delta Lake statistics:** `ANALYZE TABLE` collects column statistics used by the cost-based optimizer. Without it, Spark makes pessimistic estimates and may choose bad join strategies. Re-run after large inserts.
- **Adjacent: Data warehouse cost modeling.** Databricks is cheaper for ad-hoc analytics at scale but more expensive than DuckDB for small datasets; learn when to use query federation to external sources.
- **Revisit: Spark execution plans.** Use `EXPLAIN` and the Spark UI to see shuffle, broadcast join, and scan decisions. Slow queries are usually either full table scans (fix with partitioning/indexing) or large shuffles (fix with bucketing or join reordering).
