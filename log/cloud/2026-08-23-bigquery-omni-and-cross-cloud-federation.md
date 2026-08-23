---
date: 2026-08-23
phase: cloud
topic: BigQuery Omni and cross-cloud federation
---

# BigQuery Omni and cross-cloud federation

*Cloud platforms and storage*

## Concept

BigQuery Omni enables querying data stored outside BigQuery—in AWS S3, Azure Blob Storage, or on-premises systems—without moving it into BigQuery first. It uses BigQuery's compute engine to federate queries across cloud providers, trading latency and bandwidth costs for avoiding ETL pipelines and data duplication. This matters when you have large datasets in another cloud or legacy storage, regulatory constraints prevent centralized storage, or you need to join BigQuery native tables with external data in real time.

Without federation, you either duplicate data (high storage and sync costs), build custom connectors (engineering overhead), or accept query latency from moving data on-demand. Omni shifts the cost equation: you pay for BigQuery slot usage and cross-cloud data egress, but avoid copy-and-sync complexity. However, federated queries are slower than native BigQuery tables because data travels across cloud boundaries and Omni must coordinate compute across regions.

Understanding your query plan becomes critical. A join between a native BigQuery table and an external S3 table will push filtering and aggregation to the external source if possible, but complex transformations may serialize data back through BigQuery compute, exploding your egress costs. Cost visibility requires monitoring slot usage, bytes scanned at the external source, and egress metrics—not just query duration.

## Practice

**Problem:** You maintain `job_postings_fact` in BigQuery but your company's legacy data warehouse (on AWS) holds historical salary benchmarks in a table `aws_salary_benchmarks(job_title, percentile_50, percentile_90)`. You need to enrich current job postings with historical salary context without copying the benchmark table into BigQuery.

```sql
-- Create external connection to AWS (one-time setup)
CREATE CONNECTION `us.aws-omni-conn` AS
  CLOUD_RESOURCE (
    service_account_id='bq-omni-sa@project.iam.gserviceaccount.com'
  );

-- Grant AWS credentials via cross-account role (IAM setup)

-- Federated query: join native table with external S3 table
SELECT
  j.job_id,
  j.job_title_short,
  j.salary_year_avg,
  b.percentile_50,
  b.percentile_90,
  ROUND(100.0 * (j.salary_year_avg - b.percentile_50) / b.percentile_50, 1) AS pct_above_median
FROM `project.dataset.job_postings_fact` j
LEFT JOIN EXTERNAL_QUERY(
  'arn:aws:s3:::my-bucket/salary_benchmarks/',
  format='PARQUET',
  connection='us.aws-omni-conn'
) b
  ON LOWER(j.job_title_short) = LOWER(b.job_title)
WHERE j.job_posted_date >= '2024-01-01'
  AND j.job_work_from_home = FALSE;
```

## Notes

- **Push-down logic matters:** Omni can push simple filters (`WHERE job_posted_date >= ...`) to S3, but complex transformations may serialize the full table back through BigQuery. Always check the query plan's external vs. local compute stages.
- **Egress costs dominate:** Cross-cloud data transfer is expensive (often $0.02–0.10 per GB). A 10 GB full table scan via Omni costs $0.20–1.00 in egress alone. Partition and filter aggressively at the external source.
- **Connection security is manual:** Omni requires explicit cross-account IAM roles and service account setup. Unlike native tables, federation depends on external credentials staying valid—monitor for auth failures on scheduled queries.
- **Related: partitioning and clustering** in external tables. Parquet tables in S3 benefit from Hive-style partitioning (`s3://bucket/job_title=Engineer/salary_range=100k-120k/`) so Omni can skip irrelevant files.
- **Revisit when:** cost analysis shows egress > storage (consider copying), or when query latency < 5s regularly (native tables might be cheaper than Omni overhead).
