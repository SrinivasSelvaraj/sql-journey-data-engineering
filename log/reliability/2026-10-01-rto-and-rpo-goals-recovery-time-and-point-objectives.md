---
date: 2026-10-01
phase: reliability
topic: RTO and RPO goals: recovery time and point objectives
---

# RTO and RPO goals: recovery time and point objectives

*Quality, reliability and the professional layer*

## Concept

RTO (Recovery Time Objective) and RPO (Recovery Point Objective) are the twin pillars of data reliability. RTO is how fast you need to be back online after failure; RPO is how much data loss you can tolerate. A financial system might need RTO = 1 hour and RPO = 15 minutes, meaning you restore within 60 minutes and lose no more than 15 minutes of transactions. Without these targets, you build blindly—you don't know if hourly snapshots are sufficient or if you need continuous replication.

These objectives drive architecture decisions. High RPO (say, real-time) demands change data capture, dual writes, or event streaming. High RTO demands redundancy, failover automation, and tested runbooks. Missing these targets becomes someone's 2 a.m. incident call, and the difference between "we recovered" and "we recovered and nobody noticed" is whether you planned for it upfront.

The professional layer means owning these numbers before disaster strikes. Junior engineers build pipelines that work; senior engineers build pipelines that fail gracefully and predictably.

## Practice

**Problem:** Your `job_postings_fact` table updates daily with new job listings and salary corrections. Your analytics team queries this for dashboard freshness; your fraud detection system needs to flag duplicate postings within 30 minutes. You currently take one backup per day at midnight. Define your RTO and RPO, then show how you'd protect against a corruption event at 2 p.m.

```sql
-- Current state: daily backup only
-- Problem: 14-hour RPO, 24-hour RTO

-- Solution: Implement RPO = 30 min (fraud detection), RTO = 2 hours
-- 1. Enable continuous transaction logging (WAL/binlog)
-- 2. Create hourly incremental backups
-- 3. Maintain point-in-time recovery with transaction log

-- Hourly backup job (create table snapshot)
CREATE TABLE job_postings_fact_backup_2pm AS
SELECT * FROM job_postings_fact
WHERE CURRENT_TIMESTAMP BETWEEN '2024-01-15 14:00:00' AND '2024-01-15 15:00:00';

-- 30-min CDC pipeline for fraud detection (separate topic, same urgency)
INSERT INTO job_postings_changes_log (job_id, change_type, changed_at)
SELECT job_id, 'new_posting', CURRENT_TIMESTAMP 
FROM job_postings_fact 
WHERE job_posted_date >= CURRENT_TIMESTAMP - INTERVAL '30 minutes'
  AND NOT EXISTS (
    SELECT 1 FROM job_postings_changes_log 
    WHERE job_id = job_postings_fact.job_id
  );

-- Recovery: if corruption detected at 2:15 p.m., restore from 2:00 p.m. backup
-- and replay transaction log from 2:00 p.m. to 2:15 p.m. = 15-min data loss (within RPO)
RESTORE TABLE job_postings_fact FROM 'backup_2024_01_15_14_00_00.sql';
```

## Notes

- **Confusing RPO with RTO:** RPO is the *data loss window* you accept; RTO is the *service downtime* you accept. 15-min RPO with 4-hour RTO is valid (you restore eventually, but some data is gone). This mismatch trips up planning.
- **Forgetting to test recovery:** An untested RTO/RPO plan is fiction. Run recovery drills quarterly; a one-hour RTO means nothing if your restore takes 3 hours in production.
- **Cost-benefit blindness:** Real-time RPO demands expensive infrastructure (streaming, redundancy, replication). Know your SLA's actual business value before over-engineering.
- **Relates to:** Data retention policy, backup strategy, failover architecture, incident response playbooks, and observability (alerting on staleness).
- **Revisit after:** Your first production incident—that's when you learn what RTO/RPO *should* have been, not what you guessed.
