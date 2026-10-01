---
date: 2026-10-01
phase: reliability
topic: Disaster recovery drills and failover validation
---

# Disaster recovery drills and failover validation

*Quality, reliability and the professional layer*

## Concept

Disaster recovery (DR) drills and failover validation are systematic tests that verify your data infrastructure can withstand and recover from failures—whether that's a database crash, network partition, corrupted pipeline state, or regional outage. Unlike theoretical documentation, drills are *active rehearsals* where you intentionally break things in controlled ways to confirm recovery procedures actually work and that your team knows how to execute them.

The difference between "someone who builds pipelines" and "someone trusted to own them" crystallizes here. A builder assumes things will work; an owner knows what breaks when and has practiced the fix. Without drills, you discover gaps during real incidents when stakes are highest, when you're under pressure, and when data consumers are already angry. A single unvalidated failover assumption can cascade into hours of downtime or data loss.

Common failure modes include: primary database becomes unavailable (test read replicas and switchover time), ETL job hangs and doesn't fail gracefully (test kill-and-retry logic), schema changes break downstream consumers (test rollback procedures), or backup restoration takes longer than your RTO (recovery time objective) allows. Drills expose these gaps before production does.

## Practice

**Problem:** You have a job posting analytics pipeline that runs daily. The `job_postings_fact` table is mission-critical for reporting. Your recovery objective is 4 hours (RTO). Design a validation query that confirms your backup can be restored and queried within SLA, and that you can detect data loss during failover.

```sql
-- DR Drill: Validate backup restoration and data continuity
-- Run this after restoring backup to a staging environment

WITH backup_state AS (
  SELECT 
    COUNT(*) as total_records,
    MAX(job_posted_date) as latest_date,
    COUNT(DISTINCT job_location) as unique_locations,
    ROUND(AVG(salary_year_avg), 2) as avg_salary,
    SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) as remote_jobs
  FROM job_postings_fact_restored  -- restored backup table
),
production_snapshot AS (
  SELECT 
    COUNT(*) as total_records,
    MAX(job_posted_date) as latest_date,
    COUNT(DISTINCT job_location) as unique_locations,
    ROUND(AVG(salary_year_avg), 2) as avg_salary,
    SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) as remote_jobs
  FROM job_postings_fact_snapshot  -- snapshot taken before "failure"
)
SELECT 
  b.total_records as restored_count,
  p.total_records as expected_count,
  CASE WHEN b.total_records = p.total_records THEN 'PASS' ELSE 'FAIL' END as record_count_check,
  b.latest_date as restored_latest_date,
  p.latest_date as expected_latest_date,
  CASE WHEN b.latest_date = p.latest_date THEN 'PASS' ELSE 'FAIL' END as data_freshness_check,
  ABS(b.avg_salary - p.avg_salary) as salary_variance,
  CASE WHEN ABS(b.avg_salary - p.avg_salary) < 100 THEN 'PASS' ELSE 'FAIL' END as data_quality_check,
  CURRENT_TIMESTAMP as drill_timestamp
FROM backup_state b
CROSS JOIN production_snapshot p;
```

## Notes

- **Common mistake:** Running DR drills only on paper or documentation. Untested procedures are worse than useless—they give false confidence. Drills must include actual data, actual tools, actual network conditions.

- **RTO vs. RPO clarity:** RTO is how fast you must be back online; RPO is how much data loss you can tolerate. A 4-hour RTO doesn't help if your RPO is 1 hour and your last backup is 2 hours old. Validate both metrics in every drill.

- **Automation ownership:** Failover procedures should be runnable by script or playbook, not a 12-step manual process. If failover requires specific individuals or institutional knowledge, it will fail when those people aren't available.

- **Cross-team coordination:** DR drills expose dependencies on infrastructure, security, and platform teams. Schedule drills with all stakeholders; use them to refine communication protocols and escalation paths.

- **Revisit regularly:** Drill quarterly at minimum. Infrastructure changes, new dependencies emerge, and team memory fades. Each drill is a teaching moment—document findings and update runbooks immediately.
