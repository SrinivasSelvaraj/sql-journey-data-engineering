---
date: 2026-09-09
phase: reliability
topic: Data freshness monitoring with automated alerting
---

# Data freshness monitoring with automated alerting

*Quality, reliability and the professional layer*

## Concept

Data freshness monitoring is the practice of continuously measuring the lag between when data is generated at its source and when it arrives in your system, then triggering alerts when that lag exceeds acceptable thresholds. Without it, analysts and downstream consumers operate on stale data without knowing it—decisions get made on yesterday's information while the pipeline silently breaks.

Freshness failures are distinct from correctness failures: your data can be perfectly accurate and completely useless if it's two days old when users expect it hourly. A job postings feed that updates at 2 AM but hasn't refreshed in 36 hours means your analysts are making hiring recommendations on dead listings. The moment you move from personal projects to shared infrastructure, freshness becomes a contractual obligation.

The automated alerting piece is what separates reactive troubleshooting from proactive ownership. You need to know *before* your stakeholders complain. This requires instrumenting your pipelines with explicit freshness checks—measuring the max date in your fact tables, comparing it to the current timestamp, and escalating when the gap widens beyond your SLA.

## Practice

**Problem:** Your `job_postings_fact` table should receive new postings every 4 hours. Build a monitoring query that flags when the most recent posting is older than 6 hours, and identify which source systems may have failed.

```sql
WITH freshness_check AS (
  SELECT 
    MAX(job_posted_date) as latest_post_date,
    CURRENT_TIMESTAMP() as check_time,
    EXTRACT(HOUR FROM CURRENT_TIMESTAMP() - MAX(job_posted_date)) as hours_since_update
  FROM job_postings_fact
)
SELECT 
  latest_post_date,
  check_time,
  hours_since_update,
  CASE 
    WHEN hours_since_update > 6 THEN 'ALERT: STALE'
    WHEN hours_since_update > 4.5 THEN 'WARNING: APPROACHING SLA'
    ELSE 'HEALTHY'
  END as freshness_status,
  CASE 
    WHEN hours_since_update > 6 THEN 'escalate_to_pipeline_team'
    WHEN hours_since_update > 4.5 THEN 'log_to_monitoring_dashboard'
  END as action
FROM freshness_check;
```

Run this query on a 2-hour schedule. Wire the result to your alerting system (PagerDuty, Slack, email) when status is 'ALERT'.

## Notes

- **Freshness vs. completeness are different:** data can arrive fresh but missing entire partitions. Monitor both independently—a 1-hour-old table with 50% of expected records is worse than a 24-hour-old complete table for some use cases.
- **Partition awareness matters:** if your table is partitioned by date, the max date query can mislead you. Check both the logical max and whether recent partitions actually exist and contain non-null row counts.
- **Ties to data contracts and SLAs:** freshness monitoring is how you measure compliance against explicit agreements. Document what "fresh enough" means for each dataset (varies wildly: real-time analytics vs. monthly reports).
- **Common mistake:** setting one alert threshold for all tables. A customer transaction feed and a historical archive have utterly different freshness requirements. Configure per table, per use case.
- **Revisit:** integrate freshness metrics into your observability stack (alongside pipeline execution logs and data quality scores). A dashboard showing freshness trends over time catches subtle degradation before it becomes a crisis.
