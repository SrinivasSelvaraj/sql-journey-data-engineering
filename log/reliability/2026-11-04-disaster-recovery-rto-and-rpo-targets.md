---
date: 2026-11-04
phase: reliability
topic: Disaster recovery: RTO and RPO targets
---

# Disaster recovery: RTO and RPO targets

*Quality, reliability and the professional layer*

## Concept

RTO (Recovery Time Objective) and RPO (Recovery Point Objective) are the two metrics that define how much downtime and data loss your organization will tolerate when something fails. RTO answers "how fast must we be back online?"—measured in minutes or hours. RPO answers "how much recent data can we afford to lose?"—measured in the same units. Together, they determine your backup frequency, replication strategy, and failover architecture.

Without explicit RTO/RPO targets, you build pipelines that look healthy in the happy path but crumble under real failure modes. A nightly batch job has an RPO of ~24 hours by default; if your business discovers mid-incident that they need RPO of 1 hour, you've already failed. Similarly, RTO defines whether you need hot standby infrastructure (expensive, fast recovery) versus cold standby (cheaper, slower recovery).

The professional difference: junior engineers assume "backups exist" and move on. Senior engineers know that *untested* backups don't exist, that RPO/RTO targets must be documented in runbooks, and that these constraints shape every architectural decision—replication lag tolerance, cost-benefit of redundancy, and acceptable manual intervention time during an outage.

## Practice

**Problem:** Your job_postings_fact table is the source of truth for a recruiting dashboard. The business requires RPO of 4 hours and RTO of 30 minutes. Your current pipeline loads new postings every 24 hours via a full table scan. Competitors' data appears in your dashboard 1 day late. Design a recovery strategy that meets the targets.

```sql
-- Current state: daily full load at 2 AM
-- Problem: 24-hour RPO, unknown RTO, no incremental capability

-- Solution: Add change capture and hourly incremental loads
-- This achieves 1-hour RPO (within 4-hour requirement)

-- 1. Create a staging table with change metadata
CREATE TABLE job_postings_staging AS
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  CURRENT_TIMESTAMP AS loaded_at,
  ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY job_posted_date DESC) AS recency_rank
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '4 hours';

-- 2. Hourly incremental load (replaces 24-hour batch)
-- Run this every hour via scheduler
INSERT INTO job_postings_fact
SELECT DISTINCT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM job_postings_staging
WHERE recency_rank = 1
  AND loaded_at > (SELECT MAX(loaded_at) FROM job_postings_fact)
ON CONFLICT (job_id) DO UPDATE SET
  salary_year_avg = EXCLUDED.salary_year_avg,
  job_work_from_home = EXCLUDED.job_work_from_home;

-- 3. Point-in-time recovery: maintain 4-hour lookback archive
CREATE TABLE job_postings_archive AS
SELECT *, CURRENT_TIMESTAMP AS archived_at
FROM job_postings_fact
WHERE loaded_at >= CURRENT_TIMESTAMP - INTERVAL '4 hours';

-- 4. RTO < 30 min: restore from archive if corruption detected
TRUNCATE TABLE job_postings_fact;
INSERT INTO job_postings_fact
SELECT job_id, job_title_short, salary_year_avg, 
       job_work_from_home, job_posted_date, job_location
FROM job_postings_archive
WHERE archived_at >= CURRENT_TIMESTAMP - INTERVAL '30 minutes';
```

## Notes

- **Confusing RTO with SLA:** SLA is a business promise (99.9% uptime); RTO is the technical target. You might promise 99.9% SLA but have RTO of 4 hours—those aren't contradictory if outages are infrequent enough.
- **RPO creep:** Don't assume "smaller is better." 15-minute RPO requires more infrastructure, higher latency writes, and more frequent testing than 4-hour RPO. Document the *business reason* for your target.
- **Untested recovery is fiction:** RTO means nothing if you've never practiced the actual restore. Add quarterly disaster recovery drills to your team calendar; many "5-minute RTO" claims evaporate when tested.
- **Connects to:** BCDR (Business Continuity & Disaster Recovery) planning, replication lag monitoring, backup validation automation, and incident runbooks. These are not separate concerns.
- **Revisit when:** scaling from daily to hourly pipelines, moving to cloud, adding new downstream consumers, or experiencing your first unplanned outage (reality check on targets).
