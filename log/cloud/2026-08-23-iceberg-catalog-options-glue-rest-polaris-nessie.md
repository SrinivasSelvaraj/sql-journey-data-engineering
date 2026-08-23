---
date: 2026-08-23
phase: cloud
topic: Iceberg catalog options: Glue, REST, Polaris, Nessie
---

# Iceberg catalog options: Glue, REST, Polaris, Nessie

*Cloud platforms and storage*

## Concept

Apache Iceberg requires a **catalog** to track table metadata, snapshots, and schema evolution—it's the system-of-record for what data exists and where. The four main production options each make different tradeoffs: **AWS Glue** integrates tightly with your AWS account and bill but locks you into AWS; **REST catalogs** are cloud-agnostic and work with any object store but require you to run and manage a service; **Polaris** (Iceberg's native REST standard) unifies behavior across clouds but is still maturing; **Nessie** adds Git-like branching and time-travel on top of REST, powerful for data quality workflows but adds operational complexity.

Without a catalog, Iceberg can't atomically commit writes, validate schema changes, or garbage-collect old snapshots—you lose ACID guarantees and your storage bill balloons with orphaned files. Picking the wrong catalog often means discovering mid-query that you can't time-travel to yesterday's data, or realizing your catalog is a single point of failure with no HA option, or finding that cross-account access requires credential gymnastics that kill performance.

The decision typically hinges on three axes: **multi-cloud portability** (favor REST/Polaris/Nessie), **operational overhead** (favor Glue), and **data lineage/governance needs** (favor Nessie). In cost-sensitive workloads, remember that a self-managed REST catalog running on a t3.medium in your VPC is often cheaper than Glue's per-request pricing at scale.

## Practice

**Problem:** Your `job_postings_fact` table grows daily. After 90 days, you want to query only the last 7 days' data for the dashboard, but you also need to audit a specific salary correction from 30 days ago without reprocessing everything. With Glue, time-travel works but is slow for large snapshots; with Nessie, you'd branch at the commit before the correction and compare. How do you isolate the 7-day window and access the historical version efficiently?

```sql
-- Using Nessie branching: create an audit branch at a known timestamp
-- (Requires Nessie REST catalog configured in your Spark session)

-- Main dashboard query: current 7 days only
SELECT job_id, job_title_short, salary_year_avg, job_location
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 7 DAY
  AND job_posted_date < CURRENT_DATE;

-- Audit query: branch to 30 days ago, check before correction
SELECT job_id, salary_year_avg, job_posted_date
FROM nessie.branches.audit_30d.job_postings_fact
WHERE job_id = 12345
  AND job_posted_date BETWEEN CURRENT_DATE - 35 DAY AND CURRENT_DATE - 25 DAY;

-- (With Glue/REST: use AS OF SYSTEM TIME or snapshot ID instead of branch)
-- SELECT ... FROM job_postings_fact FOR SYSTEM_TIME AS OF '<timestamp>';
```

## Notes

- **Glue cost trap**: Pay-per-request pricing scales linearly with metadata operations; a poorly optimized ETL hitting the catalog 10× per second will surprise you on the bill. Batch metadata calls where possible.
- **REST catalog availability**: If your REST catalog goes down, all writes block; Glue spreads that risk across AWS's HA infrastructure. Nessie adds git-like distributed semantics but doesn't eliminate the bottleneck entirely.
- **Schema evolution ownership**: Nessie and Polaris let you version schema changes as commits; Glue treats schema as mutable table state. This matters when multiple teams push schema changes and you need audit trails.
- **Cold-start performance**: Querying an old Iceberg snapshot requires the catalog to reconstruct the manifest tree; REST catalogs can be slow on large tables (1000+ snapshots). Consider archiving old snapshots or pruning metadata.
- **Adjacent: data lakehouse governance** — catalog choice affects how you implement row-level security, data lineage integration (e.g., with Apache Atlas or OpenMetadata), and cross-account sharing patterns.
