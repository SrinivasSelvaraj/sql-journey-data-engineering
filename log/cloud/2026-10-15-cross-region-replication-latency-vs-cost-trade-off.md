---
date: 2026-10-15
phase: cloud
topic: Cross-region replication: latency vs cost trade-off
---

# Cross-region replication: latency vs cost trade-off

*Cloud platforms and storage*

## Concept

Cross-region replication copies data across geographically distributed data centers to improve availability and read performance for distant users, but introduces a fundamental trade-off: lower latency for reads comes at the cost of higher storage, network, and synchronization expenses. When you replicate a 500 GB table to three regions, you're paying for 1.5 TB of storage plus inter-region transfer costs; without it, users querying from distant regions experience 100–500ms latency that can break real-time dashboards or time-sensitive applications.

The cost impact is non-obvious because it compounds: you pay for storage in each region, egress charges when data leaves the primary region (often $0.02–0.04/GB), and potentially extra compute if you maintain read replicas. Replication also creates consistency challenges—eventual consistency windows mean a query in region B might see slightly stale data compared to region A, which breaks critical financial or compliance reporting if not explicitly managed.

Without replication, queries from distant regions either suffer unacceptable latency or require application-level caching, which introduces staleness risk and operational complexity. The decision to replicate should be driven by: (1) geographic distribution of users, (2) tolerance for latency (is 200ms acceptable?), and (3) read-to-write ratio (heavy read workloads justify replication; write-heavy ones don't).

## Practice

**Problem:** A recruitment analytics platform serves job posting data to users in US, EU, and APAC regions. The `job_postings_fact` table (2 GB, growing 50 MB/day) is stored in `us-east-1`. EU users report 250ms query latency; leadership wants all regions at <100ms. What queries should you replicate, and where?

```sql
-- Before: Identify your most expensive queries to replicate
SELECT 
  query_text,
  COUNT(*) as execution_count,
  AVG(query_duration_ms) as avg_latency_ms,
  SUM(bytes_scanned) as total_bytes_scanned,
  SUM(bytes_scanned) * execution_count as cost_multiplier
FROM query_audit_log
WHERE execution_date >= CURRENT_DATE - INTERVAL '30 days'
  AND query_source_region != 'us-east-1'
GROUP BY query_text
ORDER BY cost_multiplier DESC
LIMIT 10;

-- Solution: Replicate only high-value aggregates, not full table
-- Create materialized view in eu-west-1 and ap-southeast-1
CREATE MATERIALIZED VIEW job_postings_summary_replicated AS
SELECT 
  DATE_TRUNC(job_posted_date, MONTH) as month,
  job_location,
  job_work_from_home,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary,
  MAX(job_posted_date) as latest_post_date
FROM job_postings_fact
GROUP BY 1, 2, 3;

-- Refresh on schedule (hourly) in each region, not row-by-row
-- Cost: 2 GB aggregate (~200 MB per region) vs 2 GB full replicate
-- Latency: 80ms (refreshed locally) vs 250ms (cross-region query)
```

## Notes

- **Common mistake:** Replicating entire tables "just in case"—measure actual regional query patterns first; most queries may come from one region, making full replication wasteful.
- **Consistency confusion:** Read replicas with eventual consistency are fine for analytics (job posting counts), but dangerous for transactional data (application state); know your RPO/RTO requirements before replicating.
- **Adjacent topics:** This connects to materialized views (replicate *aggregates*, not raw data), query result caching (cheaper than replication for read-heavy workloads), and data locality decisions in distributed systems.
- **Cost blind spot:** Monitor inter-region data transfer costs separately; they often exceed storage costs and spike unexpectedly during backfill or failover scenarios.
- **Revisit:** When query patterns change (e.g., a new market opens), re-evaluate replication strategy; yesterday's cost-benefit analysis may no longer hold.
