---
date: 2026-09-04
phase: cloud
topic: Waste detection: unused resources and over-provisioning
---

# Waste detection: unused resources and over-provisioning

*Cloud platforms and storage*

## Concept

Waste detection identifies unused compute and storage resources that generate costs without delivering value, and surfaces over-provisioned systems running at a fraction of capacity. In cloud data platforms, this includes unused tables or columns consuming storage, queries scanning far more data than necessary, or instances sized for peak load but running idle most of the time. This matters because cloud billing is typically pay-per-use: every GB scanned, every CPU-hour, and every stored byte has a direct cost. Without systematic detection, organizations leak money through zombie tables, redundant copies of data, and inefficient query patterns that could be optimized by 10–100x with proper indexing, partitioning, or query rewriting.

The breakdown happens silently. A table created for a one-time analysis that nobody deletes still incurs storage costs. A query scanning an entire table to find 100 rows wastes I/O. An instance provisioned for a peak that never comes sits idle. Nobody notices until the monthly bill arrives or a query timeout occurs. Detection requires combining audit logs (table access frequency), query logs (data scanned vs. returned), and resource utilization metrics to answer: *Is this resource actually used? Is it sized right?*

## Practice

**Problem:** You suspect some job postings are never queried. You want to identify columns in `job_postings_fact` that are rarely selected, and find job locations that have zero queries in the past 30 days, to decide what to drop or archive.

```sql
-- Identify unused/rarely-used columns by simulating query frequency patterns
-- (In practice, use your data warehouse's query log; this example assumes a metadata table)

WITH column_usage AS (
  SELECT 'job_id' as col_name, 450000 as query_count UNION ALL
  SELECT 'job_title_short', 448000 UNION ALL
  SELECT 'salary_year_avg', 380000 UNION ALL
  SELECT 'job_work_from_home', 50000 UNION ALL
  SELECT 'job_posted_date', 420000 UNION ALL
  SELECT 'job_location', 15000  -- Low usage candidate
)
SELECT 
  col_name,
  query_count,
  ROUND(100.0 * query_count / MAX(query_count) OVER (), 1) as pct_of_max_usage
FROM column_usage
ORDER BY query_count ASC;

-- Find job locations with no queries in 30 days (over-provisioned dimension)
SELECT DISTINCT job_location
FROM job_postings_fact
WHERE job_location NOT IN (
  -- Simulate recent query access; replace with actual query log
  SELECT job_location FROM job_postings_fact 
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
  LIMIT 0  -- Placeholder: union with actual query_log table
)
LIMIT 10;
```

## Notes

- **Storage vs. compute waste differ:** unused tables waste storage (fix by archiving); over-provisioned instances waste compute (fix by right-sizing or auto-scaling). Monitor both separately.
- **Query logs are essential:** cloud platforms (BigQuery, Redshift, Snowflake) store detailed query logs including bytes scanned and returned. Audit these regularly; they reveal inefficient patterns invisible in code review.
- **Partition and cluster aggressively:** most over-scanning happens because queries hit unpartitioned tables. Partitioning by date or location, and clustering by frequently-filtered columns, can reduce bytes scanned by 90%+ without code changes.
- **Zombie data accumulates fast:** set retention policies and require explicit ownership for tables older than 90 days; automate deletion of unaccessed data to prevent silent cost creep.
- **Connects to:** query optimization (WHERE clauses, indexing), cost allocation (tagging resources by team/project), and observability (instrumenting slow queries).
