---
date: 2026-08-24
phase: cloud
topic: Multi-region replication: active-active vs active-passive
---

# Multi-region replication: active-active vs active-passive

*Cloud platforms and storage*

## Concept

Multi-region replication ensures data availability and disaster recovery by copying data across geographic locations. **Active-passive** designates one region as primary (writes/reads) and others as standby replicas (read-only until failover); recovery is manual or automated but involves switchover latency. **Active-active** allows simultaneous reads and writes across multiple regions, eliminating single points of failure but introducing complexity: write conflicts, eventual consistency windows, and higher replication lag become operational realities you must monitor and design around.

The choice matters because it directly impacts RPO (recovery point objective—how much data loss you tolerate) and RTO (recovery time objective—how long you can be down). Without replication, a regional outage means total data loss or prolonged unavailability. Active-passive is cheaper and simpler but creates a bottleneck at the primary; active-active distributes load but demands conflict resolution strategy (last-write-wins, application-level merging, or CRDTs), adds latency unpredictability, and can create hidden bugs when applications assume strongly consistent reads.

## Practice

**Problem:** Your job_postings_fact table receives new postings continuously in us-east-1, but your analytics team in eu-west-1 frequently runs slow queries because they're reading stale replicas. You need to decide whether active-passive replication (cheaper, consistent reads everywhere after brief lag) or active-active (faster local reads, but analytics might see duplicate postings from simultaneous inserts).

```sql
-- Active-passive: writes only to us-east-1, reads replicated to eu-west-1
-- Replication lag acceptable for analytics; analytics query waits for replica
SELECT job_title_short, COUNT(*) as posting_count, AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 7 DAY
  AND job_work_from_home = TRUE
GROUP BY job_title_short
ORDER BY avg_salary DESC;

-- Active-active: both regions accept writes, must deduplicate or handle conflicts
-- Add a replication_id and source_region to detect duplicates from sync lag
SELECT job_title_short, COUNT(*) as posting_count, AVG(salary_year_avg) as avg_salary
FROM (
  SELECT DISTINCT ON (job_id) *
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL 7 DAY
    AND job_work_from_home = TRUE
  ORDER BY job_id, job_posted_date DESC  -- Keep latest version
)
GROUP BY job_title_short
ORDER BY avg_salary DESC;
```

## Notes

- **Replication lag is silent:** Active-passive masks lag well; active-active exposes it through stale reads and duplicates. Monitor `pg_last_xlog_receive_location()` (PostgreSQL) or equivalent to catch divergence.
- **Write conflicts are application bugs waiting to happen:** In active-active, simultaneous updates to the same job_id from different regions can cause last-write-wins data loss. Versioning and timestamps are not enough; embed region-id + lamport clock or use event sourcing.
- **Cost is non-linear:** Active-passive pays for storage/egress once; active-active pays for bidirectional replication, conflict detection, and often more aggressive monitoring—easily 2–3× the bill.
- **Failover automation requires rehearsal:** Active-passive failover scripts (DNS cutover, promotion of standby) must be tested monthly; untested scripts fail under stress. Active-active avoids catastrophic failover but introduces chronic operational complexity.
- **Adjacent concern—read replicas vs. replication:** Read replicas are often confused with replication. Replicas are for query scaling within a region; replication is for durability across regions. Use both, but for different reasons.
