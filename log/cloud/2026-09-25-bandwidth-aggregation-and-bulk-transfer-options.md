---
date: 2026-09-25
phase: cloud
topic: Bandwidth aggregation and bulk transfer options
---

# Bandwidth aggregation and bulk transfer options

*Cloud platforms and storage*

## Concept

Bandwidth aggregation and bulk transfer options refer to strategies for moving large volumes of data efficiently between on-premises systems and cloud storage, or between cloud regions. When you transfer data piecemeal—row by row, file by file—you pay per-request fees and consume network resources inefficiently. Cloud providers charge for egress bandwidth (data leaving their infrastructure) and often impose per-request costs on storage operations; transferring 1 GB in 1 million small requests is far more expensive than one bulk operation.

This matters acutely when you're ingesting historical datasets, exporting analytics results, or replicating tables across regions. Without bulk transfer optimization, a job that should cost $20 in bandwidth can cost $200+ because you're paying thousands of small per-request fees ($0.0004 per request on AWS S3, for example). Network transfers also bottleneck: a naive row-by-row ETL might take hours when a bulk copy completes in minutes.

What breaks: query performance degrades because data isn't available yet, costs explode unexpectedly, and pipelines fail or timeout waiting for data. Understanding your transfer method is as critical as understanding your query plan.

## Practice

**Problem:** You need to export all job postings with salaries above $150k to a data warehouse in a different AWS region. A colleague wrote a Python script that reads each row, filters it, and writes it individually to S3. The job runs for 6 hours and costs $450. Optimize it using bulk transfer.

```sql
-- Instead of row-by-row processing, use CREATE TABLE AS SELECT (CTAS) 
-- with UNLOAD to bulk-write partitioned Parquet files to S3

CREATE TABLE job_postings_high_salary AS
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  YEAR(job_posted_date) AS year_partition
FROM job_postings_fact
WHERE salary_year_avg > 150000;

-- Bulk unload partitioned by year to minimize request count
UNLOAD (
  SELECT * FROM job_postings_high_salary
)
TO 's3://target-bucket/job_postings_high_salary/'
WITH (
  format = 'PARQUET',
  partitioned_by = ARRAY['year_partition'],
  compression = 'SNAPPY'
);
-- Single operation, ~50x faster, ~90% cost reduction
```

## Notes

- **Per-request costs bite harder than bandwidth**: AWS S3 charges $0.0004 per PUT; transferring 100k rows individually costs $40 just in requests, bulk operations collapse this to near-zero.
- **Compression + format matter**: Use Parquet or ORC over CSV; SNAPPY compression halves egress bandwidth costs while improving query speed on the receiving end.
- **Egress charges are region-specific**: Data leaving AWS costs money; staying within a region is free. Cross-region replication is expensive—batch it deliberately.
- **Partitioning reduces subsequent queries**: When you partition by date or category during bulk transfer, downstream queries scan only relevant files; unoptimized flat exports force full table scans.
- **Related topics**: query plan analysis (why is the export slow?), columnar storage formats, S3 Select and data filtering at the storage layer, VPC endpoints (avoid public internet for large transfers).
