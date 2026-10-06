---
date: 2026-10-06
phase: python
topic: Logging configuration: structured logs and JSON output
---

# Logging configuration: structured logs and JSON output

*Python for data engineering*

## Concept

Structured logging replaces ad-hoc string messages with consistent, machine-readable records—typically JSON—that include timestamp, severity level, logger name, message, and contextual fields. In data pipelines, this matters because unstructured logs become noise at scale: grep-based debugging fails when processing millions of rows, and you lose correlation between pipeline stages, data quality issues, and system events.

Without structured logging, you lose observability. A pipeline fails silently or produces corrupt data, and your only clue is a wall of text logs that mention neither the job ID that failed nor which transformation step introduced nulls. With JSON output, log aggregation tools (ELK, CloudWatch, Datadog) index fields automatically, enabling queries like "show me all failures for job_id=42" or "alert if any stage logs >100 errors/min."

Python's `logging` module + `pythonjsonlogger` makes this trivial: configure once at pipeline entry, then every log statement—whether from your code or third-party libraries—emits structured JSON. This survives bad input because you log the actual values, schemas, and row counts at each stage, making data quality issues immediately visible rather than hiding in downstream analytics bugs.

## Practice

**Problem:** A job posting pipeline ingests CSV files and loads them into `job_postings_fact`. Some files have missing salary data, wrong date formats, or out-of-range boolean values. You need to identify which file, which row, and which field failed—without manual inspection.

```sql
-- Logging solution: create a staging table that captures bad records
CREATE TABLE job_postings_staging_log (
  load_id STRING,
  source_file STRING,
  row_number INT,
  raw_record STRING,
  error_field STRING,
  error_reason STRING,
  logged_at TIMESTAMP
);

-- Upsert good records into fact table; log bad ones
INSERT INTO job_postings_fact
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM parsed_records
WHERE salary_year_avg IS NOT NULL 
  AND job_posted_date >= '1900-01-01' 
  AND job_work_from_home IN (true, false);

INSERT INTO job_postings_staging_log
SELECT load_id, source_file, row_number, raw_record, 
       CASE 
         WHEN salary_year_avg IS NULL THEN 'salary_year_avg'
         WHEN job_posted_date < '1900-01-01' THEN 'job_posted_date'
         WHEN job_work_from_home NOT IN ('true', 'false') THEN 'job_work_from_home'
       END AS error_field,
       CASE 
         WHEN salary_year_avg IS NULL THEN 'null or unparseable'
         WHEN job_posted_date < '1900-01-01' THEN 'date out of range'
         WHEN job_work_from_home NOT IN ('true', 'false') THEN 'invalid boolean'
       END AS error_reason,
       CURRENT_TIMESTAMP
FROM parsed_records
WHERE salary_year_avg IS NULL 
   OR job_posted_date < '1900-01-01' 
   OR job_work_from_home NOT IN (true, false);
```

## Notes

- **Don't log at INFO level for every row**—log counts and summaries instead, or you'll generate gigabytes of logs per run. Reserve INFO for stage transitions; DEBUG for per-row details only in development.
- **Structured logging connects to data lineage and observability**—knowing which records failed and why is half the battle; the other half is tracing them back to source and forward to impact.
- **Common mistake:** logging the error message but not the context (file name, job ID, row number). Always include enough context that a colleague can reproduce the failure without asking you.
- **Adjacent: schema validation, dead-letter queues, and alerting**—structured logs enable automated routing of bad records and threshold-based alerts, turning logs into an active quality system.
- **Revisit after implementing:** check that your JSON schema is consistent (don't add new fields ad-hoc), and that log volume doesn't exceed your storage budget; use sampling or tiered logging (verbose locally, summary in production).
