---
date: 2026-10-01
phase: reliability
topic: Backup strategy: frequency, retention and testing
---

# Backup strategy: frequency, retention and testing

*Quality, reliability and the professional layer*

## Concept

A backup strategy defines *how often* you capture state (frequency), *how long* you keep copies (retention), and *whether those copies actually work* (testing). Without it, a single corrupted load, malicious deletion, or hardware failure becomes irrecoverable data loss. Frequency must match your RPO (Recovery Point Objective)—how much data loss you can tolerate. Retention must match your RTO (Recovery Time Objective) and compliance rules. Testing closes the fatal gap: backups that have never been restored are backups that don't exist.

Most engineers backup *data* but forget to backup *schemas, configurations, and permissions*. A restored table without its indexes, constraints, or access rules is only half-recovered. In production, you also need to backup at multiple layers: raw source data, intermediate transforms, and final fact tables. Each has different failure modes and recovery needs.

The professional move is to *automate* backup validation into your pipeline. A daily restore test on a non-production replica costs compute but catches corruption before you need it. It's the difference between "we have backups" and "we've proven our backups work."

## Practice

**Problem:** Your `job_postings_fact` table is loaded daily. A logic error in upstream transformation corrupts 30 days of salary data. You need to restore one week of clean data without losing the last three days. How do you design this?

```sql
-- 1. Create versioned backup table with daily snapshots
CREATE TABLE job_postings_fact_backup (
  backup_date DATE,
  job_id INT,
  job_title_short VARCHAR,
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR,
  snapshot_timestamp TIMESTAMP,
  PRIMARY KEY (backup_date, job_id)
);

-- 2. Daily insert-only append (immutable log)
INSERT INTO job_postings_fact_backup
SELECT 
  CURRENT_DATE as backup_date,
  j.* ,
  CURRENT_TIMESTAMP as snapshot_timestamp
FROM job_postings_fact j;

-- 3. Restore clean week: insert rows from 7 days ago, delete corrupted rows
DELETE FROM job_postings_fact
WHERE job_posted_date BETWEEN '2024-01-15' AND '2024-01-21';

INSERT INTO job_postings_fact
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM job_postings_fact_backup
WHERE backup_date = '2024-01-21' -- Last clean snapshot
  AND job_posted_date BETWEEN '2024-01-15' AND '2024-01-21';

-- 4. Validation query: run this weekly to prove backups are usable
SELECT COUNT(*) as row_count_check, MIN(salary_year_avg) as sanity_check
FROM job_postings_fact_backup
WHERE backup_date = CURRENT_DATE - 1;
```

## Notes

- **Frequency trap:** Daily backups sound safe but are expensive. Match frequency to *change velocity* and *cost of loss*, not arbitrary schedules. A fact table loaded once daily needs daily backups; a reference table updated quarterly doesn't.

- **Retention gotcha:** Compliance (GDPR, SOX) often demands you *delete* old data, but backups must *keep* it. Document your retention tiers: keep last 30 days hot, archive months 1–12 cold, purge after 7 years.

- **The untested backup is a myth:** Schedule monthly full-restore drills on a clone environment. If you can't restore in under your RTO, your strategy failed.

- **Connects to:** incremental backups (only changed rows), point-in-time recovery (transaction logs), and disaster recovery orchestration (automation + failover).

- **Revisit:** backup costs scale with data volume—consider tiered strategies (full monthly + incremental daily) and immutable append-only logs instead of mutable snapshots.
