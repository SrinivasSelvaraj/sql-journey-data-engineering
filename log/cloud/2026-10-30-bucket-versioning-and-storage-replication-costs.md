---
date: 2026-10-30
phase: cloud
topic: Bucket versioning and storage replication costs
---

# Bucket versioning and storage replication costs

*Cloud platforms and storage*

## Concept

Bucket versioning maintains a complete history of object changes by retaining all previous versions when an object is overwritten or deleted. In cloud storage (S3, GCS, Azure Blob), this is disabled by default but enabled per bucket—once active, every write creates a new version with a unique ID rather than replacing the prior object. This consumes storage proportional to the number of versions kept: if you overwrite a 10 GB dataset daily for a month without cleanup, you pay for ~300 GB of storage instead of 10 GB.

Storage replication extends costs further by spreading data across regions or availability zones for durability and disaster recovery. Cross-region replication multiplies storage costs (one write = multiple stored copies in different locations), and egress charges apply when data moves between regions. Both features are essential for production data—accidental deletion recovery, compliance audits, disaster scenarios—but must be sized explicitly in cost forecasts or queries will mysteriously become expensive when historical versions or replicated copies are queried.

Without versioning, a failed ETL job that corrupts data in place may be unrecoverable; without replication, a regional outage makes data unavailable. The trap is enabling both without lifecycle policies (auto-delete old versions) or understanding query patterns—legacy analytics queries reading old versioned objects can balloon costs while appearing to query a single table.

## Practice

**Problem:** Your data team loads `job_postings_fact` daily via an append-only ETL. After three months, storage costs tripled and queries are slower. Investigation reveals versioning is enabled on the bucket, and multiple old versions of the manifest file and partition directories exist. You need to identify how many versions are consuming space and set a retention policy.

```sql
-- Query cloud storage metadata (example: Google Cloud Storage via BigQuery external tables)
-- First, list all versions in the bucket and calculate storage per object
SELECT
  name,
  generation,
  metageneration,
  size_bytes,
  time_created,
  CURRENT_TIMESTAMP() AS queried_at,
  CASE
    WHEN generation = 0 THEN 'live'
    ELSE 'archived_version'
  END AS version_status
FROM `project.dataset.gcs_objects_metadata`
WHERE bucket_name = 'job-postings-bucket'
  AND name LIKE 'job_postings_fact/%'
ORDER BY name, generation DESC;

-- Aggregate: total storage cost by retention age
SELECT
  name,
  COUNT(DISTINCT generation) AS version_count,
  SUM(size_bytes) / (1024*1024*1024) AS total_gb,
  MIN(time_created) AS oldest_version,
  MAX(time_created) AS newest_version
FROM `project.dataset.gcs_objects_metadata`
WHERE bucket_name = 'job-postings-bucket'
GROUP BY name
HAVING COUNT(DISTINCT generation) > 1
ORDER BY total_gb DESC;
```

**Solution:** Set a lifecycle rule on the bucket to delete non-current versions older than 30 days, and configure replication only for the `_important` subdirectory containing schema definitions, reducing replication overhead by 70%.

## Notes

- **Lifecycle policies are mandatory**: Set auto-delete for old versions (e.g., keep only 7 days) or versioning becomes a cost sink; couple this with object expiration rules for temporary work directories.
- **Egress and cross-region replication compound**: Queries reading replicated data in a secondary region incur egress charges; always check query location hints and whether your BI tool is reading from the replica.
- **Manifest and metadata files multiply the problem**: ETL frameworks (Spark, dbt) often write manifest/checkpoint files that change on every run; these create thousands of versions. Exclude them from versioning or store them separately.
- **Query plan opacity**: Slow queries on "the same table" may be reading multiple versions silently; enable query logging to see which object generations are accessed.
- **Adjacent topics**: Object locking (WORM compliance), replication lag and consistency models, versioning vs. snapshots (cheaper for some workloads), and audit logging to track who deleted what.
