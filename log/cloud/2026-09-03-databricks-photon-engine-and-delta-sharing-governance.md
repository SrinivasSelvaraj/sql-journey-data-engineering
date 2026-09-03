---
date: 2026-09-03
phase: cloud
topic: Databricks: Photon engine and Delta Sharing governance
---

# Databricks: Photon engine and Delta Sharing governance

*Cloud platforms and storage*

## Concept

**Photon** is Databricks' native C++ query engine that replaces Apache Spark's Java-based engine for dramatically faster execution—especially on columnar operations, aggregations, and joins. It's transparent to users (same SQL/DataFrame API) but can reduce query time by 2–10× and significantly lower cloud costs by reducing cluster runtime. Without understanding Photon, you might over-provision clusters or blame slow queries on data volume when the execution engine is the real bottleneck.

**Delta Sharing governance** controls who can access shared Delta tables across organizations without requiring them to run Databricks. This matters because uncontrolled sharing creates data lineage blind spots, compliance risks, and unpredictable query load on your workspace. Without governance policies, external consumers might run expensive queries against your shared tables, inflating your compute spend while you have no visibility into their access patterns.

Together, these forces shape your cost model: Photon makes your queries cheaper, but unmanaged Delta Sharing can leak that savings when external users query inefficiently. You must monitor both engine efficiency and sharing permissions to know what you're actually paying for.

## Practice

**Problem:** Your analytics team runs expensive daily aggregations on `job_postings_fact`. A partner company has access via Delta Sharing but their queries on the same table run much slower and cost more per query. You need to identify whether it's a Photon engine difference, a governance issue (they're querying unoptimized clones), or both.

```sql
-- Query 1: On your Databricks workspace with Photon enabled (default on SQL warehouses)
SELECT 
  job_work_from_home,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY
GROUP BY job_work_from_home;

-- Query 2: Check what the shared consumer actually receives (may lack Photon and statistics)
SHOW TBLPROPERTIES job_postings_fact;
-- Look for delta.lastCommitTimestamp and absence of OPTIMIZE metadata
-- If shared via Delta Sharing recipient, they see raw Parquet—no Photon acceleration

-- Solution: Create an optimized, pre-aggregated share table with Photon pre-computed
CREATE TABLE job_postings_shared AS
SELECT 
  job_work_from_home,
  job_location,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary,
  MIN(job_posted_date) as earliest_posting
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 365 DAY
GROUP BY job_work_from_home, job_location;

-- Optimize and gather statistics (Photon + recipient benefit)
OPTIMIZE job_postings_shared;
ANALYZE TABLE job_postings_shared COMPUTE STATISTICS;

-- Grant read-only access via Delta Sharing recipient
ALTER TABLE job_postings_shared OWNER TO `external_partner_recipient`;
```

## Notes

- **Photon is workspace-scoped**: SQL warehouses have it on by default; Photon doesn't accelerate queries executed by Delta Sharing recipients consuming your tables—they see Parquet files. Pre-aggregate or denormalize shared tables if cost is critical.
- **Delta Sharing has no query gates**: A recipient with read access can run full-table scans, expensive joins, or unbounded GROUP BYs. Use materialized views or restricted tables to prevent runaway costs on your dime.
- **OPTIMIZE and ANALYZE compound with Photon**: Running OPTIMIZE before sharing reduces file count and enables better statistics; Photon then uses those stats for smarter pruning. Skip this and even Photon can't help.
- **Monitor `system.billing.logs` and `system.query.history`**: Correlate slow queries with Photon enabled/disabled and Delta Sharing access to isolate cost drivers; external access often shows up as high-latency reads despite small result sets.
- **Adjacent topics**: Unity Catalog governance policies, Z-order clustering on shared tables, and query result caching—all reduce effective query cost when Photon + sharing are paired.
