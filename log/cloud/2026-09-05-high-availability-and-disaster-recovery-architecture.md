---
date: 2026-09-05
phase: cloud
topic: High availability and disaster recovery architecture
---

# High availability and disaster recovery architecture

*Cloud platforms and storage*

## Concept

High availability (HA) and disaster recovery (DR) are architectural patterns that keep systems running despite failures. HA focuses on *continuous operation* through redundancy—multiple database replicas, load balancers, and failover mechanisms—so users experience minimal or zero downtime during component failures. DR focuses on *recovery from catastrophic events*—region outages, data corruption, ransomware—by maintaining backups in geographically separated locations and documented recovery procedures (RPO: recovery point objective; RTO: recovery time objective).

Without HA/DR, a single database node failure brings down your entire application, and a region-wide outage can mean days of data loss and recovery. In cloud platforms, you pay extra for multi-AZ (availability zone) replication, cross-region backups, and managed failover—costs that scale with your RPO/RTO requirements. A slow query in a read-heavy system often reveals that your read replicas are undersized or lagging, forcing traffic back to the primary and creating a bottleneck.

Understanding HA/DR prevents over-engineering (unnecessary replication costs) and under-engineering (unacceptable downtime SLAs). The key is matching architecture to business criticality: non-critical reporting can tolerate 24-hour RPO and 4-hour RTO; transactional systems demand minutes or seconds.

## Practice

**Problem:** Your job postings table is the source of truth for a hiring dashboard. Currently, all reads and writes hit a single PostgreSQL instance in us-east-1. Every month, a 30-minute maintenance window causes the dashboard to go offline. You need to support read traffic during maintenance and survive a region failure with <1 hour recovery time.

```sql
-- HA solution: read replica in same region + cross-region standby backup
-- 1. Create synchronous read replica in different AZ (managed via cloud provider UI or:)
CREATE PUBLICATION job_postings_pub FOR TABLE job_postings_fact;

-- 2. On replica instance, subscribe to changes
CREATE SUBSCRIPTION job_postings_sub 
  CONNECTION 'dbname=job_postings host=primary-instance' 
  PUBLICATION job_postings_pub;

-- 3. Route read queries to replica (connection pooling logic in app)
-- Primary: INSERT/UPDATE/DELETE on job_postings_fact
-- Replica (read-only): SELECT queries during maintenance window
SELECT job_id, job_title_short, salary_year_avg 
FROM job_postings_fact 
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY salary_year_avg DESC;

-- 4. Cross-region backup: automated daily snapshots to us-west-2
-- (Managed via AWS RDS, Azure Database, or pg_basebackup scheduled in cron)
-- Test recovery monthly: restore snapshot, verify data integrity, delete
```

## Notes

- **Replica lag kills HA**: a read replica lagging 5 minutes behind primary means stale salary data in your dashboard. Monitor replica lag metrics; if >10s, your writes are too fast or the replica is undersized.
- **RPO vs. RTO mismatch**: backing up hourly (RPO 1hr) but only testing recovery once per year (RTO unknown) is false confidence. Automate recovery tests or accept you'll lose data/time during real incidents.
- **Cross-region cost trap**: multi-region replication and snapshots add 30–50% to database bills. Quantify your actual RTO requirement before replicating everywhere.
- **Failover automation vs. manual**: automatic failover (DNS flip, managed services) reduces RTO but can cause split-brain writes if not careful; manual failover is safer for critical systems but slower.
- **Adjacent topics**: connection pooling (PgBouncer), query routing logic (read/write split), backup verification (restore-test-delete workflows), and cloud provider SLAs (what availability they guarantee vs. what you must architect).
