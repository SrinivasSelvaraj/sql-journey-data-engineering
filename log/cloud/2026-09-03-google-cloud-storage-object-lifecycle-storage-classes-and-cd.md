---
date: 2026-09-03
phase: cloud
topic: Google Cloud Storage: object lifecycle, storage classes and CDN
---

# Google Cloud Storage: object lifecycle, storage classes and CDN

*Cloud platforms and storage*

## Concept

Google Cloud Storage (GCS) charges you for storage volume, retrieval operations, and data egress. **Storage classes** determine cost and availability: Standard (hot data, frequent access), Nearline (accessed monthly), Coldline (accessed quarterly), and Archive (rare access, 365-day minimum). **Lifecycle policies** automatically transition objects between classes or delete them based on age, reducing costs for data you touch infrequently—critical for analytics pipelines that accumulate historical data. Without lifecycle management, a data lake balloons in cost; without the right storage class, you pay premium rates for data that should be cold.

**Cloud CDN** caches GCS objects at edge locations, drastically reducing latency and egress costs for repeated reads. It matters most when non-GCP clients (web frontends, mobile apps, remote offices) repeatedly fetch the same datasets. If your BI dashboard queries a 500 MB reference table 10,000 times daily without CDN, you pay egress charges per request and wait for cross-region roundtrips. CDN flips the economics: cache hits serve from nearby edges, cutting both latency and bandwidth costs.

## Practice

**Problem:** Your job_postings_fact table grows daily. Historical data (>1 year old) is rarely queried by analysts, but recent months drive your BI tools. You're paying Standard storage rates on 2 TB of archival records. Design a cost-optimization strategy.

```sql
-- Create a GCS bucket lifecycle policy (as Terraform or gcloud command)
-- Automatically transition to Coldline after 90 days, Archive after 365 days
CREATE OR REPLACE TABLE `project.dataset.job_postings_fact_config` AS
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  CURRENT_DATE() AS loaded_date
FROM `project.dataset.job_postings_fact`
WHERE job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY);

-- Partition the table by job_posted_date for efficient pruning
-- Partition clause in CREATE TABLE:
-- PARTITION BY job_posted_date
-- CLUSTER BY job_location, job_title_short

-- Lifecycle rule (gcloud):
-- gcloud storage buckets update gs://my-bucket \
--   --add-lifecycle-condition=age=90d,action=SetStorageClass=COLDLINE \
--   --add-lifecycle-condition=age=365d,action=SetStorageClass=ARCHIVE
```

## Notes

- **Partition pruning is your friend:** partition job_postings_fact by date so queries on recent data don't scan archive partitions; pair with lifecycle to auto-archive old partitions.
- **Egress costs hide in multi-region setups:** moving data between regions costs money; if your analysts are in Europe but data lives in us-central1, CDN or regional bucket placement pays for itself.
- **Archive has retrieval latency and costs:** 1 hour to restore, $0.05 per GB retrieved; don't archive data you query weekly; suitable only for compliance holds or disaster recovery.
- **Storage class transitions are one-way-ish:** Standard → Coldline → Archive is cheap, but Archive → Standard requires manual restore; plan your retention windows upfront.
- **Adjacent: BigQuery table expiration and dataset location**—combine partition expiration with lifecycle for the full cost picture; always colocate GCS buckets with BigQuery datasets to avoid cross-region egress.
