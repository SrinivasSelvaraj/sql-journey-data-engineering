---
date: 2026-08-12
phase: pipelines
topic: Dead letter queues and quarantine tables
---

# Dead letter queues and quarantine tables

*Pipelines and orchestration*

## Concept

A dead letter queue (DLQ) or quarantine table is a dedicated holding area for records that fail validation, transformation, or loading during pipeline execution. Instead of halting the entire job or silently dropping bad data, these mechanisms capture the problematic record, its context (timestamp, pipeline stage, error message), and metadata about why it failed. This shifts the pipeline from "all-or-nothing" to "graceful degradation with visibility."

Without quarantine, you face a dilemma: fail the job and reprocess everything (wasteful), or skip the bad record silently (data loss you won't discover until analysis). A quarantine table makes failures explicit and inspectable. You can then decide whether to fix upstream data, adjust validation rules, or manually intervene—without replaying clean records.

The pattern works across message queues (Kafka, RabbitMQ), databases, and file-based workflows. The key is capturing not just the data but the *reason* it failed: schema mismatch, constraint violation, null in required field, type conversion error. This forensic detail is what makes quarantine actionable rather than just a graveyard.

## Practice

**Problem:** Your pipeline loads job postings into `job_postings_fact`. Some records have malformed `job_posted_date` values (future dates, null, invalid format), and `salary_year_avg` occasionally contains text instead of a number. Without quarantine, these rows either crash the pipeline or get coerced into defaults, hiding data quality issues.

```sql
-- Create quarantine table
CREATE TABLE job_postings_quarantine (
  quarantine_id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  captured_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  pipeline_stage VARCHAR(50),
  error_reason VARCHAR(500),
  rejected_json TEXT,
  job_id VARCHAR(100),
  job_title_short VARCHAR(100),
  salary_year_avg VARCHAR(100),
  job_work_from_home VARCHAR(10),
  job_posted_date VARCHAR(100),
  job_location VARCHAR(200)
);

-- Insert valid records; catch exceptions and route to quarantine
INSERT INTO job_postings_fact (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT job_id, job_title_short, CAST(salary_year_avg AS INT), 
       CAST(job_work_from_home AS BOOLEAN), CAST(job_posted_date AS DATE), job_location
FROM staging_job_postings
WHERE salary_year_avg ~ '^\d+$'  -- only numeric
  AND job_posted_date ~ '^\d{4}-\d{2}-\d{2}$'  -- ISO format
  AND job_posted_date::DATE <= CURRENT_DATE
  AND job_location IS NOT NULL;

-- Route failures to quarantine (example; implementation varies by tool)
INSERT INTO job_postings_quarantine (pipeline_stage, error_reason, rejected_json, job_id, salary_year_avg, job_posted_date)
SELECT 'validation', 
       CASE WHEN salary_year_avg !~ '^\d+$' THEN 'salary not numeric'
            WHEN job_posted_date::DATE > CURRENT_DATE THEN 'posted_date is future'
            WHEN job_location IS NULL THEN 'location is null'
            ELSE 'unknown' END,
       to_jsonb(t.*),
       job_id, salary_year_avg, job_posted_date
FROM staging_job_postings t
WHERE salary_year_avg !~ '^\d+$'
   OR job_posted_date !~ '^\d{4}-\d{2}-\d{2}$'
   OR job_posted_date::DATE > CURRENT_DATE
   OR job_location IS NULL;

-- Inspect quarantine
SELECT error_reason, COUNT(*) as fail_count FROM job_postings_quarantine 
GROUP BY error_reason ORDER BY fail_count DESC;
```

## Notes

- **Quarantine is not a sink; it's a checkpoint.** Treat it as a signal for investigation. Set up alerts on quarantine growth; a spike often indicates upstream schema or data quality changes you need to address immediately.
- **Store the original value, not the coerced value.** Keep `salary_year_avg` as a string in quarantine, not as NULL or 0. You need to see exactly what came in to diagnose root cause.
- **Log the pipeline context.** Include job_run_id, timestamp, source system, and transformation step. This lets you trace back to the exact batch and tooling that failed, making retries and debugging faster.
- **Balance strictness and pragmatism.** Overly strict validation fills quarantine without business value. Collaborate with data owners to decide: is a future date a data error or legitimate? Should missing location fail the record or default to "Remote"?
- **Connect to observability and alerting.** Quarantine tables pair naturally with dbt tests, Great Expectations, or custom anomaly detection. If quar
