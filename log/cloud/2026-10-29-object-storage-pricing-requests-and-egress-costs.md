---
date: 2026-10-29
phase: cloud
topic: Object storage pricing: requests and egress costs
---

# Object storage pricing: requests and egress costs

*Cloud platforms and storage*

## Concept

Object storage (S3, GCS, Azure Blob) charges for API requests and data egress separately from storage capacity. Every GET, PUT, LIST, or DELETE operation incurs a small per-request fee (typically $0.0004–$0.005 per 1000 requests), and downloading data out of the region costs $0.02–$0.12 per GB. These costs are hidden in slow queries because you pay per operation, not per byte scanned—a single inefficient query can trigger thousands of LIST calls or massive egress.

The problem surfaces when your ETL pipeline repeatedly scans the same files (no caching), when you filter after egress instead of before, or when you accidentally cross regions. A job that queries 100 GB of parquet files across 10,000 small objects can cost $2–5 in requests alone; add cross-region egress and you're at $10+. Without understanding this, you optimize for query speed and accidentally optimize for cost explosion.

This matters most in data lakes where you control partitioning and can push filters to the storage layer, and in ML pipelines where the same historical dataset gets downloaded repeatedly. It also explains why "the same query" runs cheap in one region and expensive in another.

## Practice

**Problem:** Your daily job posting analysis queries all records from `job_postings_fact` stored in S3 (parquet, partitioned by `job_posted_date`), but you only need postings from the last 7 days. Without partition pruning, you scan 2 years of data (50,000 objects). How do you reduce request and egress costs?

```sql
-- Bad: full table scan, triggers LIST on all partitions + GET on 50k files
SELECT job_title_short, AVG(salary_year_avg)
FROM s3://my-bucket/job_postings_fact/
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 7 DAY
GROUP BY job_title_short;

-- Good: filter on partition column *before* reading
SELECT job_title_short, AVG(salary_year_avg)
FROM s3://my-bucket/job_postings_fact/job_posted_date>='{CURRENT_DATE - 7d}'
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 7 DAY
GROUP BY job_title_short;

-- Better: use Iceberg/Delta with partition pushdown built in
SELECT job_title_short, AVG(salary_year_avg)
FROM iceberg_job_postings
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 7 DAY
GROUP BY job_title_short;
```

## Notes

- **Partition pruning is not optional:** queries must filter on partition columns at scan time, not after egress. Athena, BigQuery, and Snowflake on object storage all support partition elimination—use it.
- **LIST requests are the hidden killer:** listing 50k objects costs $0.025 even if you read none. Avoid wildcards in production; query by explicit partition path instead.
- **Egress asymmetry:** downloading from object storage is expensive; uploading is free. This is why most pipelines do heavy transforms *inside* the cloud region, then write results back.
- **Cross-region federation is a cost trap:** querying S3 in `us-west-2` from Redshift in `us-east-1` incurs egress fees plus latency. Always co-locate compute and storage in the same region.
- **Caching and temporary tables:** materialized views and local temp tables (Parquet on compute instance disk) eliminate repeated scans and requests; the cost of writing once beats 50 expensive reads.
