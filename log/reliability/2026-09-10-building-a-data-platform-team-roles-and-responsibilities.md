---
date: 2026-09-10
phase: reliability
topic: Building a data platform team: roles and responsibilities
---

# Building a data platform team: roles and responsibilities

*Quality, reliability and the professional layer*

## Concept

The difference between a pipeline builder and a pipeline owner is accountability for what happens *after* deployment. A builder writes code that works once; an owner designs for failure modes, monitors continuously, and responds when things break at 2 AM. This shift requires moving from "does it run?" to "does it run *reliably* under production load, with incomplete data, schema changes, and upstream delays?"

Ownership surfaces when you must answer: What happens if the source system is down for 6 hours? If a field suddenly contains nulls? If job posting volume spikes 10x? A builder might not have considered these; an owner has guard rails, alerts, and playbooks. This is where data quality becomes non-negotiable—not because it's nice, but because stakeholders depend on your table to be fresh, complete, and trustworthy by 8 AM every day.

Without this layer, platforms accumulate "surprise" failures that erode confidence. Teams stop trusting data, analytics teams build redundant pipelines, and operational decisions get delayed or made on stale numbers. Ownership prevents this by embedding reliability and observability into the pipeline's design, not bolted on afterward.

## Practice

**Problem:** Your `job_postings_fact` table feeds a hiring dashboard used by 12 teams. You notice job posting volume spikes unpredictably (ranging from 50 to 5,000 per day), and the dashboard sometimes shows data 2+ hours stale. You need to detect when freshness breaks, validate data quality at load time, and alert before users notice.

```sql
-- Owner mindset: add quality gates and observability
CREATE OR REPLACE TABLE job_postings_fact AS
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  CURRENT_TIMESTAMP() as _loaded_at,
  CASE 
    WHEN salary_year_avg IS NULL THEN 'missing_salary'
    WHEN job_location IS NULL OR job_location = '' THEN 'missing_location'
    WHEN job_posted_date > CURRENT_DATE() THEN 'future_date'
    ELSE 'valid'
  END as _quality_flag
FROM raw_job_postings
WHERE job_posted_date >= CURRENT_DATE() - INTERVAL 90 DAY;

-- Alert if freshness degrades
CREATE OR REPLACE TABLE _pipeline_health AS
SELECT 
  'job_postings_fact' as table_name,
  MAX(_loaded_at) as last_refresh,
  CURRENT_TIMESTAMP() as check_time,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(_loaded_at), MINUTE) as freshness_minutes,
  COUNTIF(_quality_flag != 'valid') as row_quality_issues,
  COUNT(*) as total_rows
FROM job_postings_fact
GROUP BY 1;
```

This owner-level approach embeds validation, tracking, and the data to trigger alerts when SLAs slip.

## Notes

- **Builder trap:** Writing the query once and assuming it will always work. Ownership means testing the pipeline against data anomalies (nulls, duplicates, late arrivals, schema drift).
- **Monitoring ≠ fixing:** Adding `_loaded_at` and `_quality_flag` columns is cheap; the real work is setting alert thresholds and owning the response (manual rerun, rollback, root cause investigation).
- **SLA before code:** Before writing pipelines, agree on freshness (how stale is acceptable?), completeness (what % null is tolerable?), and timeliness (when must it be ready?). Ownership means defending these contracts.
- **Connects to:** data contracts, observability platforms (dbt checks, Great Expectations, custom alerting), incident response playbooks, and stakeholder communication.
- **Revisit:** How do you handle late-arriving data? Backfill strategy? Who owns the alert pager? These aren't technical questions—they're ownership questions.
