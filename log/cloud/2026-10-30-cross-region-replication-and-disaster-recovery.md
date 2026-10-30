---
date: 2026-10-30
phase: cloud
topic: Cross-region replication and disaster recovery
---

# Cross-region replication and disaster recovery

*Cloud platforms and storage*

## Concept

Cross-region replication copies your data automatically across geographically distant cloud regions, ensuring availability when a region fails and reducing latency for users far from your primary location. In cloud platforms like AWS (S3 cross-region replication), Azure (geo-redundant storage), or GCP (multi-region buckets), you pay for every byte transferred between regions—often 2–3x the cost of local storage—plus the compute to replicate. Without replication, a regional outage (network partition, data center fire, provider issue) makes your data inaccessible; with it, queries fail over to a read replica, but you only notice the cost when analyzing your bill.

The choice between replication strategies directly impacts both resilience and expense. Synchronous replication (writes block until confirmed in the replica) guarantees consistency but adds latency and cost; asynchronous replication completes writes faster but risks losing recent data if the primary fails. For analytics, eventual consistency is often acceptable; for operational databases, you may need stronger guarantees. Query slowness often traces back to replication lag—a query hitting a stale replica—or cross-region data movement that wasn't cached or partitioned.

## Practice

**Problem:** Your analytics team queries `job_postings_fact` from a US-East primary region, but users in EU-West experience 800ms latency. You want to replicate selectively (only recent postings, not historical data) to save on replication costs while improving regional performance.

```sql
-- Create a partitioned view that routes queries by region
-- Primary (US-East): all data
-- Replica (EU-West): only last 90 days to control replication volume

CREATE TABLE job_postings_fact_eu_replica AS
SELECT 
  job_id, 
  job_title_short, 
  salary_year_avg, 
  job_work_from_home, 
  job_posted_date, 
  job_location
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days';

-- Index on frequently filtered columns to reduce scan time
CREATE INDEX idx_job_postings_eu_date 
  ON job_postings_fact_eu_replica(job_posted_date DESC);

-- Application logic (pseudo-code in your data layer):
-- IF user_region = 'EU-West' AND query_date_range > 90 days ago
--   THEN query replica for recent data, fall back to primary for historical
-- ELSE query primary region
```

This reduces replication traffic by ~70% (90 days ≈ 25% of typical data) while keeping hot data local.

## Notes

- **Cost trap:** Cross-region egress is often billed per GB; a nightly full sync of a 500 GB table can cost $200–500/month. Always replicate *subsets* (by date, partition, or access pattern) unless strong consistency is mandatory.
- **Replication lag is invisible in tests:** A query may succeed in dev (synchronous) but mysteriously return stale data in production (asynchronous). Always test with realistic lag thresholds (5–30 seconds typical).
- **RPO vs. RTO:** Recovery Point Objective (how much data you can lose) and Recovery Time Objective (how fast you come back online) drive your replication strategy. Asynchronous replication has higher RPO; synchronous has higher latency. Document both explicitly.
- **Connects to:** read replicas, sharding by region, caching strategies (CDN vs. database replica), and failover automation—if your replica goes stale, you need monitoring and automated alerts, not manual investigation.
- **Revisit when:** your cloud bill spikes unexpectedly, users report stale data, or a region outage actually happens and your failover is slower than your SLA allows.
