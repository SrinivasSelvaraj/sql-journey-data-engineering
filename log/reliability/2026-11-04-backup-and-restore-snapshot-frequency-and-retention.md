---
date: 2026-11-04
phase: reliability
topic: Backup and restore: snapshot frequency and retention
---

# Backup and restore: snapshot frequency and retention

*Quality, reliability and the professional layer*

## Concept

Snapshot frequency and retention policy determine how quickly you can recover from data loss and how far back you can go. Frequency answers "how often do I capture state?"—daily, hourly, or transaction-log-based. Retention answers "how long do I keep them?"—7 days, 90 days, indefinite. Together they define your recovery time objective (RTO) and recovery point objective (RPO).

Without a deliberate policy, you either keep nothing and lose everything on corruption, or keep everything and hemorrhage storage costs. The gap between snapshot times is data you cannot recover; the gap between now and oldest retention is history you cannot audit. Most data corruption goes unnoticed for days, so a 3-day retention is often too short for fact tables, but a 5-year retention on staging tables is waste.

This is where you stop being a pipeline author and start being a data owner. Authors write code that works today. Owners design systems that still work when they're asleep, when storage fills up, when someone runs a DELETE without a WHERE clause, or when a source system resets to zero.

## Practice

**Problem:** Your `job_postings_fact` table is corrupted—a bad ETL run loaded 50,000 rows with NULL salary_year_avg on Tuesday morning. It wasn't caught until Friday. You need to restore to Monday 11:59 PM. Your current snapshot strategy is one per week (Sunday 2 AM). Can you recover?

**Solution:** Implement daily snapshots with 30-day retention, and a transaction log for point-in-time recovery.

```sql
-- Create immutable daily snapshot
CREATE TABLE job_postings_fact_snapshot AS
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  CURRENT_DATE AS snapshot_date,
  NOW() AS snapshot_timestamp
FROM job_postings_fact
WHERE CURRENT_DATE = DATE(job_posted_date);

-- Partition by date for efficient pruning
ALTER TABLE job_postings_fact_snapshot 
PARTITION BY snapshot_date;

-- Retention policy: drop snapshots older than 30 days
DELETE FROM job_postings_fact_snapshot 
WHERE snapshot_date < CURRENT_DATE - INTERVAL '30 days';

-- Restore from Friday 11:59 PM snapshot (snapshot_date = 2024-01-04)
TRUNCATE TABLE job_postings_fact;
INSERT INTO job_postings_fact
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, 
       job_posted_date, job_location
FROM job_postings_fact_snapshot
WHERE snapshot_date = '2024-01-04';
```

## Notes

- **Frequency trap:** Daily snapshots for slowly-changing dimensions are overkill; hourly for fast-moving fact tables is often too sparse if you have sub-hour SLAs. Match frequency to change rate and business impact, not gut feeling.

- **Storage math:** 1 GB fact table × 30 daily snapshots = 30 GB. Know your cost ceiling before you commit to retention. Delta compression (storing only changes) cuts this dramatically but adds restore complexity.

- **Adjacent topics:** Immutability, audit logs, CDC (Change Data Capture), and data lineage all reinforce snapshots. Snapshots alone don't tell you *who* or *why*; you need logs for that.

- **Common mistake:** Snapshots in the same database as production. One cascade failure wipes both. Use separate storage (S3, cold warehouse tier, or secondary database). Include the snapshot in your disaster recovery drill.

- **Revisit:** Layered retention (daily for 30 days, weekly for 2 years, monthly for 7 years) balances recovery agility with storage cost. Implement this as your pipeline matures.
