---
date: 2026-09-22
phase: pipelines
topic: Quarantine tables for anomalies and reprocessing
---

# Quarantine tables for anomalies and reprocessing

*Pipelines and orchestration*

## Concept

A quarantine table isolates records that fail validation checks during pipeline execution, separating "good" data that proceeds downstream from "suspicious" data that requires investigation. Instead of blocking the entire pipeline or silently dropping records, quarantined data lands in a staging table with metadata about *why* it failed, enabling both immediate alerting and deferred reprocessing once root causes are understood.

This matters most when data quality rules are strict but upstream sources are imperfect—late-arriving corrections, schema drift, or transient API errors shouldn't cascade into pipeline failures or corrupt your fact tables. A quarantine pattern lets you draw a hard line: if a record doesn't pass validation, it never enters production analytics, but it's also never lost.

Without quarantine tables, you face three bad outcomes: (1) pipelines fail entirely on a single bad record, blocking all downstream jobs; (2) you skip validation to keep pipelines running, and bad data pollutes your fact tables; or (3) you drop invalid records silently and never know what you missed.

## Practice

**Problem:** Your `job_postings_fact` ingestion pipeline receives records with null salaries, impossible dates (future-dated postings), and malformed location strings. You need to load clean records into the fact table on schedule while capturing invalid ones for the data team to fix.

```sql
-- Main fact table (clean data only)
CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR,
  salary_year_avg INT NOT NULL,
  job_work_from_home BOOLEAN,
  job_posted_date DATE NOT NULL,
  job_location VARCHAR NOT NULL,
  loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Quarantine table (failed records + reason)
CREATE TABLE job_postings_quarantine (
  job_id INT,
  raw_payload JSON,
  salary_year_avg INT,
  job_posted_date DATE,
  job_location VARCHAR,
  failure_reason VARCHAR NOT NULL,
  quarantined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  reprocessed_at TIMESTAMP NULL
);

-- Insert with validation; route failures to quarantine
INSERT INTO job_postings_fact (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM staging_job_postings
WHERE salary_year_avg IS NOT NULL
  AND job_posted_date <= CURRENT_DATE
  AND job_location IS NOT NULL
  AND LENGTH(job_location) > 0;

-- Capture what didn't make it
INSERT INTO job_postings_quarantine (job_id, raw_payload, salary_year_avg, job_posted_date, job_location, failure_reason)
SELECT 
  job_id,
  TO_JSON(staging_job_postings),
  salary_year_avg,
  job_posted_date,
  job_location,
  CASE
    WHEN salary_year_avg IS NULL THEN 'Missing salary'
    WHEN job_posted_date > CURRENT_DATE THEN 'Future-dated posting'
    WHEN job_location IS NULL OR LENGTH(job_location) = 0 THEN 'Invalid location'
  END AS failure_reason
FROM staging_job_postings
WHERE salary_year_avg IS NULL
  OR job_posted_date > CURRENT_DATE
  OR job_location IS NULL
  OR LENGTH(job_location) = 0;

-- After issues are fixed upstream, reprocess with UPDATE tracking
UPDATE job_postings_quarantine
SET reprocessed_at = CURRENT_TIMESTAMP
WHERE job_id IN (SELECT job_id FROM job_postings_fact WHERE loaded_at > CURRENT_TIMESTAMP - INTERVAL 1 HOUR);
```

## Notes

- **Don't quarantine forever:** Set a retention policy; after 30 days unresolved quarantines should trigger an alert or auto-expire. Otherwise the table becomes a junk drawer and the data team ignores it.

- **Metadata is essential:** Store the raw payload (JSON), not just failed columns. The reason *why* it failed (null vs. out-of-range vs. format mismatch) must be explicit; vague failure reasons are useless for debugging.

- **Connects to:** dead-letter queues (Kafka pattern), observability dashboards (alert on quarantine volume spikes), schema validation frameworks (JSON Schema, Great Expectations) that feed quarantine logic.

- **Common mistake:** treating quarantine as a dumping ground for "weird data." Quarantine should be *specific and rule-based*; if you're quarantining >5% of records, your validation rules are probably too strict or your upstream data quality is truly broken and needs fixing at the source.

- **Reprocessing logic:** Keep a `reprocessed_at` timestamp and optionally a `reprocess_attempt_count` to handle retry loops gracefully. Always diff quarantined records against their fact-table
