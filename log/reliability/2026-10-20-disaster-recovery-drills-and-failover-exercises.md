---
date: 2026-10-20
phase: reliability
topic: Disaster recovery drills and failover exercises
---

# Disaster recovery drills and failover exercises

*Quality, reliability and the professional layer*

## Concept

Disaster recovery drills and failover exercises are simulated outages where you intentionally break production systems—or their backups—to verify that your recovery procedures actually work. This is not testing in staging; it's validating that documented runbooks match reality, that data can be restored to a known good state, and that your team can execute under pressure without improvisation.

Without drills, recovery plans become fiction. A pipeline owner who has never restored from backup doesn't know if their backup is corrupt, if their restore scripts have hardcoded paths, or if permissions are misconfigured. A team that hasn't practiced failover doesn't know who owns which decision, how long restoration actually takes, or what communication channels exist during an outage. Drills expose these gaps before real disasters do.

This is what separates operators from owners: ownership means you've proven your system recovers, not just that you believe it should.

## Practice

**Problem:** Your `job_postings_fact` table is the source of truth for a critical reporting dashboard. Your backup strategy is daily snapshots. You need to simulate complete data loss and verify you can restore to a specific point in time.

```sql
-- Step 1: Identify your snapshot point (e.g., data as of yesterday end-of-day)
SELECT MAX(job_posted_date) as last_safe_checkpoint
FROM job_postings_fact
WHERE job_posted_date < CURRENT_DATE;

-- Step 2: Create a restore-validation table (simulating recovery)
CREATE TABLE job_postings_fact_restored AS
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM job_postings_fact_backup_2024_01_14
WHERE job_posted_date <= '2024-01-13';

-- Step 3: Validate row counts and checksums match expectations
SELECT COUNT(*) as restored_rows, 
       SUM(CAST(salary_year_avg AS BIGINT)) as salary_checksum
FROM job_postings_fact_restored;

-- Step 4: Compare against documented baseline (from your last known good state)
-- Expected: 847,293 rows, salary_checksum = 2,156,847,392,100
-- If mismatch: your backup is stale or corrupt

-- Step 5: Time this exercise and document it
-- Record: restore duration, validation duration, any permission/access issues
```

## Notes

- **Undiscovered single points of failure**: Drills often reveal that backups exist but restore scripts only run on one person's laptop, or that the backup storage account has the wrong region lock.
- **RTO vs. RPO mismatch**: You'll discover your Recovery Time Objective (4 hours) doesn't match your Recovery Point Objective (1 hour data loss tolerance) until you actually try restoring.
- **Permissions and credentials rot**: By the time you need a backup, the service account may have lost permissions, the encryption key may have been rotated, or the connection string may be stale.
- **Adjacent topics**: monitoring and alerting (you need to detect the disaster first), change management (who approves a restore?), and observability (can you prove data integrity post-recovery?).
- **Revisit quarterly**: Infrastructure and access policies change; a drill that passed in Q3 may fail in Q4 if your data warehouse migrated to a new region.
