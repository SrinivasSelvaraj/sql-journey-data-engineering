---
date: 2026-09-23
phase: cloud
topic: Egress costs and data residency constraints
---

# Egress costs and data residency constraints

*Cloud platforms and storage*

## Concept

Egress costs are charges incurred when data leaves a cloud provider's network—typically measured in GB transferred out. Within a region, data movement is free or cheap; crossing regions or exiting to the internet costs $0.01–$0.12 per GB depending on the provider and destination. Data residency constraints mandate that certain data stay within specific geographic boundaries for compliance (GDPR, HIPAA, data sovereignty laws), which directly conflicts with cost optimization and can trap you in expensive data transfer patterns.

The trap emerges when you query data in one region but your analytics tool, BI dashboard, or downstream service lives in another. A single JOIN across regions or a report pulling 50 GB monthly can silently cost thousands. Without awareness, you optimize for query speed and miss the egress bill. Worse, residency rules may *force* redundancy—keeping copies in multiple regions to satisfy both compliance and performance, multiplying storage costs.

This matters most at scale (terabytes+), in multi-region deployments, and when integrating cloud data with on-premises systems or third-party APIs. The fix: co-locate compute and storage, understand your cloud provider's pricing model, and design schemas and queries to minimize cross-boundary traffic.

## Practice

**Problem:** Your job_postings_fact table (500 GB) lives in us-west-2, but your European analytics team queries it daily via a BI tool in eu-west-1. Each daily full refresh costs ~$5 USD in egress. You need to serve both regions without doubling the bill or violating EU data residency rules.

```sql
-- Solution: Create a regional replica in eu-west-1 with partitioning to minimize sync costs
-- 1. Create a materialized view or table in eu-west-1 with only essential columns and recent partitions
CREATE TABLE job_postings_eu AS
SELECT 
  job_id, 
  job_title_short, 
  salary_year_avg, 
  job_work_from_home, 
  job_posted_date, 
  job_location
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY
  AND job_location LIKE '%EU%';

-- 2. Set up incremental sync (daily) instead of full copy
-- Only push new/updated rows via AWS DataSync, Snowflake Iceberg replication, or DMS
INSERT INTO job_postings_eu
SELECT * FROM job_postings_fact 
WHERE job_posted_date = CURRENT_DATE - INTERVAL 1 DAY;

-- 3. Route queries by residency: EU queries hit job_postings_eu, US queries hit original
-- Use a routing layer (application logic or view) to send queries to the right region
SELECT job_title_short, AVG(salary_year_avg) as avg_sal
FROM job_postings_eu
WHERE job_location LIKE '%EU%'
  AND job_posted_date >= '2024-01-01'
GROUP BY job_title_short;
```

## Notes

- **Egress hidden in aggregation:** Aggregating 1 TB to produce 1 MB result still costs the full 1 TB egress; push filters and GROUP BY down to the source region first.
- **Residency ≠ replication:** Residency means data *origin* and *primary copy* stay put; you can cache/replicate if the source region remains compliant.
- **Cross-region JOINs are silent killers:** A JOIN between us-west and eu-west tables triggers full table broadcast to the join region; always co-locate fact and dimension tables.
- **Monitor CloudTrail/audit logs:** Set up cost alerts on egress metrics (AWS: check data transfer in CloudWatch; GCP: monitor egress in Billing; Azure: review data transfer costs per region).
- **Adjacent topics:** query federation (Trino, Athena federated queries), global secondary indexes, CDN caching for frequently accessed datasets, and cloud provider pricing tiers (commitment discounts apply to egress too).
