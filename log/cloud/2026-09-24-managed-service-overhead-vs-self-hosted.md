---
date: 2026-09-24
phase: cloud
topic: Managed service overhead vs self-hosted
---

# Managed service overhead vs self-hosted

*Cloud platforms and storage*

## Concept

Managed services (RDS, BigQuery, Redshift) abstract away infrastructure but charge per resource consumed—compute, storage, query scans. Self-hosted (PostgreSQL on EC2, Spark clusters) require you to provision and maintain instances, but you pay a flat rate regardless of actual load. The tradeoff: managed services auto-scale and handle failover, but slow queries cost more money because they consume more CPU or scan more data. You must understand what drives costs in your platform: in BigQuery it's bytes scanned; in RDS it's instance type and storage; in Redshift it's node-hours regardless of query efficiency.

The breakdown happens when you optimize for the wrong metric. A self-hosted setup rewards efficient query planning because it doesn't change your monthly bill. A managed service rewards both efficiency *and* data reduction—materializing aggregates, partitioning tables, and filtering early become cost-control mechanisms, not just performance tweaks. Without this awareness, a single unoptimized JOIN scanning billions of rows can silently inflate your bill by thousands of dollars.

## Practice

**Problem:** You run a weekly report on `job_postings_fact` counting job postings by title and average salary. On BigQuery, this query scans 50GB every run. Your billing alert fires. Optimize it.

```sql
-- Before: full table scan ~50GB
SELECT 
  job_title_short,
  COUNT(*) as posting_count,
  ROUND(AVG(salary_year_avg), 2) as avg_salary
FROM job_postings_fact
WHERE job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY job_title_short;

-- After: partition + materialized view
CREATE OR REPLACE TABLE job_postings_fact
PARTITION BY DATE(job_posted_date)
CLUSTER BY job_title_short AS
SELECT * FROM `project.dataset.job_postings_fact`;

-- Materialized view (scans only partition, ~500MB instead of 50GB)
CREATE MATERIALIZED VIEW job_summary_weekly AS
SELECT 
  job_title_short,
  COUNT(*) as posting_count,
  ROUND(AVG(salary_year_avg), 2) as avg_salary,
  CURRENT_DATE() as report_date
FROM job_postings_fact
WHERE job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY job_title_short;

-- Query now uses materialized view, minimal scan
SELECT * FROM job_summary_weekly;
```

## Notes

- **Managed cost leak:** Unfiltered `SELECT *` or missing `WHERE` clauses on date partitions are invisible in self-hosted but visible in your credit card. Always push predicates down early.
- **Materialized views vs. caching:** Managed services benefit from pre-computed tables and views; self-hosted benefits from query result caches. Know which tool your platform optimizes.
- **Hidden compute:** RDS read replicas, BigQuery slots, and Redshift concurrency scaling all shift cost from linear to fixed-rate or vice versa—revisit pricing model when scaling.
- **Data gravity matters:** Moving data out of a managed service (to train a model, analyze elsewhere) often triggers egress charges; self-hosted has no such penalty.
- **Monitoring as requirement:** On managed services, logging slow/expensive queries isn't optional—set up query audit logs and cost attribution from day one.
