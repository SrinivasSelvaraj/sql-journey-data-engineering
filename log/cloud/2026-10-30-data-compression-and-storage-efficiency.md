---
date: 2026-10-30
phase: cloud
topic: Data compression and storage efficiency
---

# Data compression and storage efficiency

*Cloud platforms and storage*

## Concept

Data compression reduces storage footprint by encoding repeated or redundant patterns, directly lowering cloud storage costs and I/O time during query execution. In cloud platforms (BigQuery, Redshift, Snowflake), you pay per GB scanned—compressed data means fewer bytes read, faster queries, lower bills. Without compression, a 100 GB uncompressed table might scan 100 GB on every query; the same table compressed to 20 GB scans only 20 GB, cutting query costs by 80%. Compression becomes critical when working with text-heavy columns (job titles, descriptions), high-cardinality dimensions, or large historical datasets that rarely change. Modern columnar formats (Parquet, ORC) apply compression automatically, but understanding what compresses well—and what doesn't—helps you design schemas and partition strategies that maximize efficiency.

## Practice

**Problem:** Your `job_postings_fact` table has grown to 50 GB uncompressed. Queries filtering by `job_location` and `job_work_from_home` are slow and expensive. How do you identify compression opportunities and optimize storage?

```sql
-- Check current table size and compression ratio
SELECT
  table_name,
  ROUND(size_bytes / POW(10, 9), 2) AS size_gb,
  ROUND(size_bytes / POW(10, 9), 2) AS uncompressed_estimate
FROM `project.dataset.__TABLES__`
WHERE table_name = 'job_postings_fact';

-- Optimize: partition by job_location (high-cardinality filter), 
-- cluster by job_work_from_home (Boolean, low-cardinality)
CREATE OR REPLACE TABLE `project.dataset.job_postings_fact`
PARTITION BY DATE(job_posted_date)
CLUSTER BY job_work_from_home, job_location AS
SELECT * FROM `project.dataset.job_postings_fact_staging`
ORDER BY job_posted_date, job_work_from_home, job_location;

-- Verify: query now scans only relevant partitions/clusters
SELECT COUNT(*), AVG(salary_year_avg)
FROM `project.dataset.job_postings_fact`
WHERE job_posted_date >= '2024-01-01'
  AND job_work_from_home = TRUE
  AND job_location = 'New York, NY';
```

## Notes

- **Columnar format is your baseline:** Parquet and ORC compress by column type; numeric and Boolean columns compress ~10–20×, text ~3–5×. Always store raw data in columnar format, not CSV or JSON.
- **Partition and cluster before compression:** Partitioning reduces bytes scanned; compression reduces storage cost. Together they cut both dimensions of your bill.
- **String columns are cheap to compress but expensive to scan:** Compressing `job_title_short` saves disk but doesn't help if you filter on it frequently—cluster instead.
- **Compression algorithm trade-offs:** Snappy is fast; gzip/deflate is smaller but slower. Cloud platforms choose for you; know your query speed vs. storage cost tolerance.
- **Revisit: query patterns drive schema design.** Monitor slow queries (cloud logs, EXPLAIN plans) to identify which filters matter; cluster on those, partition on time or high-cardinality dimensions that naturally filter large ranges.
