---
date: 2026-10-28
phase: pipelines
topic: Error handling and task failure notifications
---

# Error handling and task failure notifications

*Pipelines and orchestration*

## Concept

Error handling in data pipelines means catching failures early, logging them clearly, and enabling safe reruns without data corruption or duplication. Without explicit error handling, a pipeline that crashes mid-execution leaves you with incomplete loads, orphaned transactions, and no visibility into what broke. This matters most at scale: a daily job that silently drops 10% of records will poison downstream analytics for weeks before anyone notices.

Fail loudly means exposing errors immediately rather than letting bad data propagate silently. Task failure notifications—emails, Slack messages, or dashboard alerts—ensure someone acts on problems within hours, not days. Safe reruns require idempotency: designing tasks so re-executing them on the same input produces the same state (no duplicate inserts, no partial updates). Explaining failures means structured logging that captures the exact row, transformation step, and error message so debugging doesn't require guessing.

## Practice

**Problem:** Daily pipeline loads job postings into `job_postings_fact`. Some rows have NULL `salary_year_avg` values. The job currently crashes on NULL, and when it reruns, duplicate rows get inserted because there's no upsert logic. You need to handle NULLs gracefully, log which records failed validation, and make the load idempotent.

```sql
-- Idempotent load with error handling and logging

CREATE TEMP TABLE staging_job_postings AS
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  CURRENT_TIMESTAMP AS load_timestamp,
  CASE 
    WHEN salary_year_avg IS NULL THEN 'MISSING_SALARY'
    WHEN job_posted_date IS NULL THEN 'MISSING_DATE'
    WHEN job_location IS NULL THEN 'MISSING_LOCATION'
    ELSE 'VALID'
  END AS validation_status
FROM raw_job_postings
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 day';

-- Log validation failures for alerting
INSERT INTO pipeline_errors (pipeline_name, error_type, record_id, error_message, logged_at)
SELECT 
  'job_postings_daily',
  validation_status,
  job_id,
  CONCAT('Validation failed: ', validation_status),
  CURRENT_TIMESTAMP
FROM staging_job_postings
WHERE validation_status != 'VALID';

-- Upsert valid records (idempotent via MERGE or DELETE+INSERT)
DELETE FROM job_postings_fact 
WHERE job_id IN (
  SELECT job_id FROM staging_job_postings WHERE validation_status = 'VALID'
);

INSERT INTO job_postings_fact
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM staging_job_postings
WHERE validation_status = 'VALID';

-- Log success
INSERT INTO pipeline_logs (pipeline_name, status, record_count, logged_at)
SELECT 'job_postings_daily', 'SUCCESS', COUNT(*), CURRENT_TIMESTAMP
FROM staging_job_postings
WHERE validation_status = 'VALID';
```

## Notes

- **Idempotency trap:** Don't rely on IGNORE or SKIP errors—they hide data loss. Always delete-then-insert or use MERGE to ensure reruns are truly safe and produce identical results.
- **Validation before load:** Separate validation from transformation. Catch schema mismatches, NULLs, and type errors in staging tables before touching production, giving you a clear audit trail.
- **Structured logging is mandatory:** Log job IDs, row counts, error codes, and timestamps in a dedicated errors table. Unstructured logs in text files won't scale for alerting or root cause analysis.
- **Alert threshold tuning:** A single missing value might be acceptable (log and continue), but 50% NULLs signals a data quality crisis (fail the job). Define thresholds per pipeline.
- **Adjacent topics:** Dead-letter queues (quarantine bad records), circuit breakers (stop retrying after N failures), and SLA monitoring (track how long errors go unnoticed before someone acts).
