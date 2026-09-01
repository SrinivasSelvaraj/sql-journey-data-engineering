---
date: 2026-09-01
phase: pipelines
topic: Idempotency: designing pipelines safe to rerun
---

# Idempotency: designing pipelines safe to rerun

*Pipelines and orchestration*

## Concept

Idempotency means a pipeline produces the same output regardless of how many times it runs. In data engineering, this is critical because failures are inevitable—network timeouts, schema changes, partial writes—and you need to safely retry without duplicating data or leaving the system in an inconsistent state. Without idempotency, a failed job that partially loaded 10,000 records forces a manual cleanup or a full rollback, eating hours of debugging time.

Idempotent pipelines are built on immutable operations: **replace** instead of append, use **natural keys** to detect duplicates, employ **deterministic logic** that doesn't depend on run order or timestamp. A pipeline that inserts into a table is not idempotent; one that truncates and reloads, or upserts on a unique constraint, is.

Downstream consumers also benefit. If your fact table is guaranteed idempotent, dashboards and reports can safely refresh without fear of double-counted metrics. This shifts your mental model from "is my pipeline still running?" to "when was my pipeline last successfully completed?"

## Practice

**Problem:** A daily job loads job postings from an API into `job_postings_fact`. The API may return duplicate records, the job may crash mid-load, and it must be safe to re-trigger without manual intervention. How do you ensure no duplicates accumulate and reruns don't cause issues?

```sql
-- Idempotent approach: use a staging table + merge/upsert pattern
CREATE TEMP TABLE job_postings_staging AS
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM external_api_source
WHERE job_posted_date = CURRENT_DATE;

-- Upsert: update existing, insert new (keyed on job_id + job_posted_date)
MERGE INTO job_postings_fact AS target
USING job_postings_staging AS source
ON target.job_id = source.job_id 
  AND target.job_posted_date = source.job_posted_date
WHEN MATCHED THEN
  UPDATE SET 
    job_title_short = source.job_title_short,
    salary_year_avg = source.salary_year_avg,
    job_work_from_home = source.job_work_from_home,
    job_location = source.job_location
WHEN NOT MATCHED THEN
  INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
  VALUES (source.job_id, source.job_title_short, source.salary_year_avg, source.job_work_from_home, source.job_posted_date, source.job_location);

DROP TABLE job_postings_staging;
```

## Notes

- **Append-only is a trap:** INSERT-only tables are simple until they're not; prefer MERGE/upsert or daily partition replacement for idempotency at scale.
- **Natural keys are foundational:** Without a reliable unique key (e.g., `job_id + job_posted_date`), you cannot detect or prevent duplicates. Avoid synthetic surrogate keys alone.
- **Staging tables isolate risk:** Validate and deduplicate in staging before touching production. If the merge fails, staging is discarded and the job can safely retry.
- **Connects to: exactly-once semantics, transaction boundaries, data lineage.** Idempotency pairs with clear run timestamps and audit logs to explain *when* each record was last touched.
- **Revisit: deduplication logic, slowly changing dimensions (SCD), and time-travel queries** when dealing with late-arriving or corrected data.
