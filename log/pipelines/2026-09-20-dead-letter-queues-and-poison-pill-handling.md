---
date: 2026-09-20
phase: pipelines
topic: Dead letter queues and poison pill handling
---

# Dead letter queues and poison pill handling

*Pipelines and orchestration*

## Concept

A **dead letter queue (DLQ)** is a separate storage location for messages or records that fail processing after exhausting retry attempts. A **poison pill** is a single malformed or incompatible record that breaks downstream logic repeatedly—the DLQ prevents it from halting the entire pipeline.

Without DLQs, a single bad record (corrupt JSON, NULL primary key, schema violation, out-of-range value) causes the entire batch to fail and roll back. You retry the job, it fails on the same record, creating a loop. The pipeline stalls, alerts fire, and you lose visibility into what actually broke. With a DLQ, you isolate the poison pill, log its context, and let clean records flow through while you investigate asynchronously.

This matters most in high-volume, always-on pipelines where stopping to debug one record is unacceptable. Data warehouses, event streaming systems, and SaaS integrations rely on DLQs to separate "data quality issues" (quarantine and triage) from "pipeline failures" (fix and rerun).

## Practice

**Problem:** Your `job_postings_fact` table receives daily inserts from an external API. Occasionally a posting has `salary_year_avg = -999` (data quality flag) or `job_posted_date` is in the future. These violate business rules and cause downstream BI queries to error. You need to skip invalid rows, log them, and alert without halting the load.

```sql
CREATE TABLE job_postings_fact_dlq (
  job_id INT,
  job_title_short VARCHAR(100),
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(100),
  rejected_reason VARCHAR(500),
  rejected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO job_postings_fact
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM staging_job_postings
WHERE salary_year_avg > 0
  AND job_posted_date <= CURRENT_DATE
  AND job_id IS NOT NULL;

INSERT INTO job_postings_fact_dlq
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location,
  CASE 
    WHEN salary_year_avg <= 0 THEN 'Invalid salary: ' || salary_year_avg
    WHEN job_posted_date > CURRENT_DATE THEN 'Future posting date: ' || job_posted_date
    WHEN job_id IS NULL THEN 'Missing job_id'
  END AS rejected_reason,
  CURRENT_TIMESTAMP
FROM staging_job_postings
WHERE salary_year_avg <= 0
   OR job_posted_date > CURRENT_DATE
   OR job_id IS NULL;
```

## Notes

- **Don't DLQ everything preventable:** validate schema and nullability upstream (in ingestion, before queuing). DLQ is for business-logic or data-quality edge cases, not schema errors.
- **Set alerts on DLQ growth:** a sudden spike in rejections signals upstream breakage or a supplier change. Monitor DLQ volume as a canary metric.
- **Replay strategy matters:** quarantine the poison pill with full context (raw payload, timestamp, source), so you can fix validation rules, backfill, and reprocess without data loss.
- **Connects to:** schema enforcement (validate early), observability (log rejection reasons), idempotency (reprocessing the same DLQ record twice should be safe), and circuit breakers (stop retrying after N failures).
- **Revisit:** how to automate DLQ triaging (e.g., auto-correct known patterns vs. escalate to humans) and whether your DLQ is a table, topic, or S3 bucket—design depends on volume and recovery speed.
