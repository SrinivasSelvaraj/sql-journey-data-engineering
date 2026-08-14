---
date: 2026-08-14
phase: cloud
topic: Disaster recovery and RPO/RTO for data
---

# Disaster recovery and RPO/RTO for data

*Cloud platforms and storage*

## Concept

Disaster recovery planning requires understanding **RPO (Recovery Point Objective)** and **RTO (Recovery Time Objective)**. RPO is the maximum acceptable data loss, measured in time—how far back you're willing to restore (e.g., "lose no more than 1 hour of data"). RTO is how quickly you must be operational again after failure (e.g., "back online within 30 minutes"). Together they dictate your backup strategy, replication frequency, and infrastructure redundancy costs.

In cloud platforms, these metrics directly affect your bill. Continuous replication to a standby region costs significantly more than nightly snapshots, but nightly snapshots mean RPO measured in hours, not seconds. Without defining these upfront, teams either over-invest in unnecessary redundancy or discover mid-crisis that their RPO/RTO targets are impossible to meet. A financial database might need RPO of 5 minutes and RTO of 15 minutes; a data warehouse might tolerate RPO of 24 hours and RTO of 4 hours—and the second is vastly cheaper.

## Practice

**Problem:** Your job_postings_fact table grows by ~50GB daily and is critical for hiring analytics. Your SLA requires RPO of 6 hours and RTO of 1 hour. Nightly snapshots won't meet your RPO. Design a backup and recovery strategy.

```sql
-- Solution: Incremental backup strategy with transaction log shipping
-- 1. Full snapshot daily at 2 AM (baseline)
-- 2. Continuous transaction log backups every 15 minutes (meets 6hr RPO)
-- 3. Test restore procedure weekly to verify RTO achievable

-- Create immutable backup table for transaction logs
CREATE TABLE job_postings_backup_log (
  backup_id INT,
  backup_timestamp TIMESTAMP,
  operation_type VARCHAR(10), -- INSERT, UPDATE, DELETE
  affected_job_id INT,
  change_data JSON,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Schedule hourly incremental export
EXPORT DATA OPTIONS(
  uri='gs://backup-bucket/job_postings/incremental/2024-01-15-*/job_postings_*.parquet',
  overwrite=false,
  format='PARQUET'
) AS
SELECT * FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE() - 7
  AND CAST(job_posted_date AS TIMESTAMP) > (
    SELECT MAX(backup_timestamp) FROM job_postings_backup_log
  );

-- Recovery test: restore to 6 hours ago
CREATE OR REPLACE TABLE job_postings_recovered AS
SELECT * FROM `project.dataset.job_postings_fact@-21600000` -- 6hr snapshot
UNION ALL
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date
FROM job_postings_backup_log
WHERE backup_timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 6 HOUR);
```

## Notes

- **Confusing RPO/RTO:** RPO answers "how much data can I lose?" (point in time), RTO answers "how long until I'm back up?" (duration). They're independent—you can have low RPO with high RTO if you use slow restore methods.
- **Cloud cost trap:** Automated replication (RPO < 1 hour) to a secondary region costs 2–3× storage. Always audit whether your SLA actually requires it or if incremental backups suffice.
- **Testing is mandatory:** An untested backup strategy is fiction. Run quarterly restore drills using realistic data volumes to catch RTO overruns before they matter.
- **Connect to:** Query performance monitoring (slow queries might indicate backup processes contending for resources), cost allocation (label backups by criticality tier), and data retention policies (decide when old backups can be deleted).
- **Revisit when:** Adding new critical tables, changing SLA, or after any outage—measure actual recovery performance and adjust strategy accordingly.
