---
date: 2026-09-10
phase: reliability
topic: Portfolio projects that signal engineering maturity
---

# Portfolio projects that signal engineering maturity

*Quality, reliability and the professional layer*

## Concept

Maturity in data engineering isn't about knowing more tools—it's about owning reliability end-to-end. A junior engineer builds pipelines that work on happy path. A senior engineer builds pipelines that *fail gracefully*, are *observable*, and can be *debugged by someone else at 3am*. This means: comprehensive logging and monitoring, explicit error handling and retry logic, data quality checks at ingestion and output, schema versioning, and runbooks for common failures.

When this matters most is when your pipeline touches production systems or informs critical decisions. A bug in an internal analytics dashboard is educational. A bug in a data product that charges customers or gates hiring decisions is a career event. Without this layer, pipelines degrade silently—bad data propagates downstream, stakeholders lose trust, and you spend more time firefighting than building.

The professional layer is what separates "I built something that works" from "I built something the team can depend on." It's visible in your portfolio through tests, alerting configuration, deployment documentation, and honest postmortems of things that broke and how you fixed them.

## Practice

**Problem:** You're building a daily pipeline that ingests job postings and flags records where `salary_year_avg` is missing or `job_posted_date` is in the future. Currently, your pipeline silently skips bad rows. Design a solution that surfaces data quality issues while preventing corrupt data from reaching downstream tables.

```sql
-- Step 1: Staging layer with quality checks
WITH raw_ingestion AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    CURRENT_TIMESTAMP AS ingestion_timestamp
  FROM source_raw_job_postings
),

quality_checks AS (
  SELECT 
    *,
    CASE WHEN salary_year_avg IS NULL THEN 'salary_missing' END AS quality_issue_salary,
    CASE WHEN job_posted_date > CURRENT_DATE THEN 'future_date' END AS quality_issue_date,
    CASE WHEN job_id IS NULL OR job_title_short IS NULL THEN 'missing_key_field' END AS quality_issue_keys
  FROM raw_ingestion
),

-- Step 2: Route valid rows to fact table
valid_rows AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    ingestion_timestamp,
    'PASSED' AS quality_status
  FROM quality_checks
  WHERE quality_issue_salary IS NULL
    AND quality_issue_date IS NULL
    AND quality_issue_keys IS NULL
),

-- Step 3: Capture failures for monitoring/alerting
failed_rows AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_posted_date,
    job_location,
    ingestion_timestamp,
    CONCAT_WS('; ', 
      quality_issue_salary, 
      quality_issue_date, 
      quality_issue_keys
    ) AS failure_reason,
    'FAILED' AS quality_status
  FROM quality_checks
  WHERE quality_issue_salary IS NOT NULL
     OR quality_issue_date IS NOT NULL
     OR quality_issue_keys IS NOT NULL
)

-- Load valid rows to fact table
INSERT INTO job_postings_fact
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM valid_rows;

-- Log failures for alerting
INSERT INTO data_quality_log (job_id, failure_reason, quality_status, check_timestamp)
SELECT job_id, failure_reason, quality_status, ingestion_timestamp FROM failed_rows;

-- Trigger alert if failure rate exceeds threshold
INSERT INTO pipeline_alerts (alert_type, alert_message, severity)
SELECT 
  'HIGH_FAILURE_RATE',
  CONCAT('Job postings pipeline: ', 
    ROUND(100 * COUNT(CASE WHEN quality_status = 'FAILED' THEN 1 END) / COUNT(*), 2),
    '% of records failed quality checks'),
  'WARNING'
FROM (SELECT quality_status FROM valid_rows UNION ALL SELECT quality_status FROM failed_rows)
HAVING COUNT(CASE WHEN quality_status = 'FAILED' THEN 1 END) / COUNT(*) > 0.05;
```

## Notes

- **Common mistake:** Failing silently or logging to `/dev/null`. Always write failures somewhere queryable. Someone will need to debug this, and "I don't know what went wrong" is not an acceptable answer.

- **Schema versioning matters:** Job postings schema will change (new fields, renamed columns, type changes). Plan for backward compatibility early. Document your versioning strategy in your portfolio.

- **Alert fatigue is real:** Set thresh
