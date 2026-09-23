---
date: 2026-09-23
phase: cloud
topic: Object lifecycle policies and cost optimization
---

# Object lifecycle policies and cost optimization

*Cloud platforms and storage*

## Concept

Object lifecycle policies automatically transition or delete data based on age, access patterns, or custom conditions. On cloud platforms (AWS S3, GCP Cloud Storage, Azure Blob), this prevents paying for data you no longer actively use. Without lifecycle policies, historical backups, logs, and raw data accumulate indefinitely, inflating storage costs by 3–10× within a year.

Lifecycle policies matter most when your data warehouse ingests continuously: daily job postings, event logs, or sensor data. You want recent data in hot storage (standard tier, low latency, high cost) but month-old snapshots can move to cold storage (cheaper, slower). Set policies at ingestion time, not after the problem appears—retroactive cleanup is manual and error-prone.

Without lifecycle management, query performance also suffers. S3/GCS scans can hit rate limits or timeout when scanning thousands of unnecessary small files. Partitioning by date and pairing it with lifecycle rules keeps both your bill and query latency predictable.

## Practice

**Problem:** Your `job_postings_fact` table ingests daily via Parquet files partitioned by `job_posted_date`. After 18 months, you have 550 GB in S3, but queries only touch the last 90 days. Storage costs are $0.023/GB/month. Set a policy to move files older than 90 days to Glacier and delete after 2 years.

```sql
-- Define lifecycle policy (pseudo-SQL, typically done via AWS CLI or Terraform)
-- For S3 path: s3://my-warehouse/job_postings_fact/job_posted_date=YYYY-MM-DD/

CREATE LIFECYCLE POLICY job_postings_archive AS
  TRANSITION TO GLACIER
    AFTER 90 DAYS
    WHERE job_posted_date < CURRENT_DATE - 90
  EXPIRATION
    AFTER 730 DAYS
    WHERE job_posted_date < CURRENT_DATE - 730;

-- In Terraform/CloudFormation:
-- s3_object_lifecycle_configuration {
--   rule {
--     id = "archive_old_postings"
--     filter { prefix = "job_postings_fact/" }
--     transition { days = 90, storage_class = "GLACIER" }
--     expiration { days = 730 }
--   }
-- }

-- Verify impact: query only recent data with partition pruning
SELECT job_id, salary_year_avg
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - 90;
```

## Notes

- **Mistake:** Setting lifecycle policies on the entire bucket instead of specific prefixes; you may accidentally archive data you need.
- **Mistake:** Choosing Glacier without testing retrieval latency; restoring a month of old data takes 1–12 hours and costs extra.
- **Connection:** Ties directly to partitioning strategy—date-based partitions make lifecycle rules automatic and predictable.
- **Connection:** Monitor with cost allocation tags; know which tables/projects drive your bill before optimizing.
- **Revisit:** Learn Intelligent-Tiering (auto-moves based on access) as an alternative to manual policies; useful for unpredictable query patterns.
