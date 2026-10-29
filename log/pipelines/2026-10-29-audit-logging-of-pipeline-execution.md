---
date: 2026-10-29
phase: pipelines
topic: Audit logging of pipeline execution
---

# Audit logging of pipeline execution

*Pipelines and orchestration*

## Concept

Audit logging captures detailed execution metadata about pipeline runs—what executed, when, who triggered it, how long it took, what succeeded or failed, and why. This is distinct from business-level logging; it tracks the *pipeline itself*, not the data flowing through it. Without audit logs, you lose the ability to investigate why a transformation produced wrong results three days ago, whether a job reran accidentally, or which environment a dataset came from.

Audit logs become critical when pipelines fail silently or partially. A job may complete with exit code 0 while processing zero rows. A transformation might succeed on 99% of batches and skip the rest without notification. Audit logs are your evidence trail: they let you correlate job start/end times with data freshness issues, trace a bad metric back to a specific pipeline version, and prove to stakeholders that you *did* run the job on schedule.

The minimal audit log captures: pipeline name, run_id (unique identifier), start_time, end_time, status (success/failure/partial), row counts in/out, and error message (if any). Store these in a dedicated table, not console output. This becomes your source of truth for debugging and compliance.

## Practice

**Problem:** Your `job_postings_fact` table is stale and reporting the wrong salary averages. You need to prove whether the daily ETL pipeline ran yesterday, how many rows it processed, and whether it encountered errors.

```sql
-- Create audit log table
CREATE TABLE pipeline_audit_log (
  run_id STRING NOT NULL,
  pipeline_name STRING NOT NULL,
  start_time TIMESTAMP NOT NULL,
  end_time TIMESTAMP,
  status STRING,
  rows_read BIGINT,
  rows_written BIGINT,
  error_message STRING,
  environment STRING,
  triggered_by STRING
);

-- Log a successful run
INSERT INTO pipeline_audit_log 
VALUES (
  'job_postings_etl_20250117_001',
  'job_postings_etl',
  CAST('2025-01-17 02:00:00' AS TIMESTAMP),
  CAST('2025-01-17 02:15:30' AS TIMESTAMP),
  'success',
  15420,
  15388,
  NULL,
  'production',
  'airflow_scheduler'
);

-- Query to investigate staleness
SELECT 
  pipeline_name,
  MAX(end_time) as last_successful_run,
  CURRENT_TIMESTAMP() - MAX(end_time) as hours_since_last_run,
  rows_written
FROM pipeline_audit_log
WHERE pipeline_name = 'job_postings_etl'
  AND status = 'success'
GROUP BY pipeline_name;

-- Check for partial failures or dropped rows
SELECT 
  run_id,
  rows_read,
  rows_written,
  ROUND(100.0 * (rows_read - rows_written) / rows_read, 2) as drop_percentage,
  error_message
FROM pipeline_audit_log
WHERE pipeline_name = 'job_postings_etl'
  AND status IN ('success', 'partial')
ORDER BY start_time DESC
LIMIT 10;
```

## Notes

- **Common mistake:** Logging only failures. Log *every* run with row counts—a successful run that writes zero rows is a silent failure waiting to happen.
- **Partial success is invisible by default.** Always calculate input vs. output rows and flag drops >threshold. A job may exit cleanly while losing 30% of records due to validation errors.
- **Connects to:** data quality frameworks (Great Expectations, dbt tests) which should *feed* your audit log, not replace it. Audit logs answer "did it run?"; tests answer "is it correct?".
- **Environment matters.** Tag audit logs with environment (dev/staging/prod) to prevent cross-environment confusion when debugging; a test run can look like production data.
- **Retention and querying.** Keep audit logs indefinitely for compliance, but partition by date for performance. Index on (pipeline_name, start_time, status) to make investigation fast.
