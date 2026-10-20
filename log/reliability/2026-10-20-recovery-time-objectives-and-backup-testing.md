---
date: 2026-10-20
phase: reliability
topic: Recovery time objectives and backup testing
---

# Recovery time objectives and backup testing

*Quality, reliability and the professional layer*

## Concept

Recovery Time Objective (RTO) and Recovery Point Objective (RPO) are the twin measures of how much disruption your business can tolerate when a data pipeline fails. RTO is how long you have to restore service; RPO is how much data loss is acceptable (measured in time—e.g., "we can lose 4 hours of records"). Without defining these, you're guessing at backup frequency and retention, often spending too much or too little.

Backup testing is not optional—it's the only way to know your RTO is real. A backup that has never been restored is just a file sitting on disk. When a production table corrupts, a schema breaks mid-pipeline, or a cloud region fails, you discover whether your restore actually works in minutes, not months. This is the difference between "we have backups" and "we can recover."

The professional layer requires you to own both sides: understand what RTO/RPO your stakeholders actually need (not what they say offhand), then architect and *test* backups to meet it. This includes documenting recovery runbooks, practicing restores under time pressure, and versioning your backup strategy alongside your code.

## Practice

**Problem:** Your `job_postings_fact` table is critical for daily reporting. A buggy transformation runs at 2 PM and corrupts salary data for all records posted in the last 7 days. You have an RTO of 1 hour and RPO of 4 hours. Design and test a recovery approach.

```sql
-- Step 1: Create versioned backup table (append-only, immutable snapshot)
CREATE TABLE job_postings_fact_backup_20250120_1400 AS
SELECT * FROM job_postings_fact;

-- Step 2: Implement point-in-time recovery via transaction log
-- Assume your pipeline records start/end timestamps
CREATE TABLE pipeline_execution_log (
    execution_id INT PRIMARY KEY,
    table_name VARCHAR,
    execution_start_ts TIMESTAMP,
    execution_end_ts TIMESTAMP,
    status VARCHAR,
    row_count_affected INT,
    backup_location VARCHAR
);

-- Step 3: Restore from 4-hour-old backup (RPO boundary)
-- This runs in your recovery runbook
BEGIN TRANSACTION;
DELETE FROM job_postings_fact 
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7 days';

INSERT INTO job_postings_fact
SELECT * FROM job_postings_fact_backup_20250120_1000  -- Last good snapshot before 2 PM corruption
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7 days';

COMMIT;

-- Step 4: Validate recovery (before declaring success)
SELECT COUNT(*) as restored_rows FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7 days';
-- Compare against backup SELECT COUNT(*) to confirm row count matches
```

## Notes

- **Testing must simulate failure**, not just verify the backup exists. Run a monthly restore in a staging environment under time pressure; document how long it actually takes.
- **RTO and RPO drive architecture, not the other way around.** If RTO = 15 min but your restore takes 45 min, you need active-passive replication or read replicas, not just backups.
- **Backup testing reveals hidden dependencies**—foreign keys, permissions, downstream assumptions—that a simple file copy won't catch. A restore that succeeds technically but breaks downstream jobs is a restore that fails.
- **Connect this to observability**: pipeline execution logs, backup success metrics, and restore drills belong in your monitoring stack, not in Slack messages.
- **Revisit after incidents**: every outage teaches you what your real RTO is, what your team can actually execute under stress, and where runbooks are incomplete.
