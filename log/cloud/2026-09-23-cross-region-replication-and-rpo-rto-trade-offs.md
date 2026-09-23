---
date: 2026-09-23
phase: cloud
topic: Cross-region replication and RPO/RTO trade-offs
---

# Cross-region replication and RPO/RTO trade-offs

*Cloud platforms and storage*

## Concept

Cross-region replication copies data across geographically distant cloud regions to survive regional failures and reduce latency for distant users. Two metrics govern the trade-off: **RPO (Recovery Point Objective)** is the maximum acceptable data loss (how fresh must the replica be?), and **RTO (Recovery Time Objective)** is how quickly you must restore service after a failure. Synchronous replication guarantees RPO ≈ 0 but adds latency to every write; asynchronous replication is fast but risks losing recent commits if the primary region fails before data ships to replicas.

The cost is real: every replicated byte doubles (or triples) your storage bill, replication traffic consumes network bandwidth, and failover automation requires monitoring and orchestration. Without replication, a regional outage—cloud provider hardware failure, network cut, data center fire—means total unavailability and data loss. For analytics pipelines, this is often acceptable (reruns are cheap); for operational databases serving user traffic, it is not.

The hidden cost appears when you choose the wrong RPO/RTO. Over-provisioning (synchronous replication everywhere, sub-second failover) is expensive and slows writes. Under-provisioning (replication every 24 hours, manual failover) leaves you vulnerable and embarrassed during an incident.

## Practice

**Problem:** Your `job_postings_fact` table lives in `us-east-1`. A regional outage occurs at 14:00 UTC; you discover it at 14:15 UTC. Your RTO is 30 minutes and RPO is 1 hour. Hourly snapshots are copied to `eu-west-1`, but the last snapshot completed at 13:00 UTC. Can you meet your SLA?

```sql
-- RPO check: 14:00 failure - 13:00 last snapshot = 1 hour data loss (equals RPO, acceptable but tight)
-- RTO check: manual failover takes 20 minutes + application reconfiguration 10 min = 30 min (meets RTO)

-- Query to audit replication lag in production:
SELECT 
  region,
  table_name,
  last_snapshot_time,
  CURRENT_TIMESTAMP - last_snapshot_time AS replication_lag_minutes,
  CASE 
    WHEN CURRENT_TIMESTAMP - last_snapshot_time > INTERVAL '60 minutes' THEN 'BREACH'
    ELSE 'OK'
  END AS rpo_status
FROM replication_audit_log
WHERE table_name = 'job_postings_fact'
ORDER BY last_snapshot_time DESC
LIMIT 1;

-- Solution: increase snapshot frequency from hourly to every 30 minutes to match RPO.
-- Monitor replication_lag_minutes; alert if it exceeds 25 minutes (75% of RPO).
```

## Notes

- **Synchronous replication hides latency cost**: writes block until acks arrive from all replicas. For a table receiving 10k inserts/second, even 50ms cross-region latency becomes a bottleneck; measure write latency before and after enabling replication.
- **RPO and RTO are not the same**: low RPO (frequent snapshots) does not guarantee low RTO if failover is manual. Automate failover logic to stay within RTO.
- **Replication amplifies query costs on the replica region**: if you replicate to save reads during an outage, expect 2–3× query cost until you optimize statistics and indexes on the replica.
- **Connects to:** backup vs. replication (backups are restore-only; replicas serve reads), eventual consistency models, and blast radius scoping (replicate only critical tables, not everything).
- **Revisit if:** you add a third region (replication chain vs. hub-and-spoke topology matters for consistency), or if failover testing reveals that RTO assumptions were wrong—human validation steps are often slower than automation.
