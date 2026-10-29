---
date: 2026-10-29
phase: pipelines
topic: Pipeline versioning and safe deployments
---

# Pipeline versioning and safe deployments

*Pipelines and orchestration*

## Concept

Pipeline versioning means immutably tagging code, schemas, and dependencies at each deployment so you can pinpoint what changed when something breaks. Without it, you cannot confidently rerun a failed job (does it use the old logic or new?) or explain why yesterday's output differs from today's. In data engineering, this is critical because pipelines often run on schedules; if a job fails at 2 AM and you've deployed three times since then, you need to know which version actually ran.

Safe deployments pair versioning with practices like schema validation, gradual rollouts, and idempotent reruns. A pipeline that "fails loudly" exposes schema mismatches or logic errors immediately rather than silently producing bad data downstream. Idempotency—ensuring a rerun produces the same result without duplication—is essential because you will need to rerun failed jobs, and consumers expect consistency.

Without these safeguards, a single bad deployment cascades: downstream teams consume corrupt data, you cannot pinpoint the culprit, and reruns either duplicate records or skip them entirely. Versioning acts as your forensic record and your safety net.

## Practice

**Problem:** Your `job_postings_fact` table is ingested daily via an Airflow DAG. A developer pushes a change to add a `job_salary_currency` column to the transformation logic, but the database schema hasn't been updated yet. The job runs, silently drops the new column, and data is lost. When you rerun the job after fixing the schema, you cannot tell if the rerun used the old or new code.

**Solution:**

```sql
-- Version your schema and code together
-- In your dbt_project.yml or pipeline config, set a version tag:
-- version: 1.2.3

-- Create a pipeline metadata table to track runs
CREATE TABLE IF NOT EXISTS pipeline_runs (
  run_id STRING PRIMARY KEY,
  pipeline_name STRING,
  pipeline_version STRING,
  schema_version STRING,
  run_timestamp TIMESTAMP,
  status STRING,
  error_message STRING
);

-- Add a schema version column to your fact table
ALTER TABLE job_postings_fact ADD COLUMN IF NOT EXISTS schema_version STRING;

-- In your transformation (dbt or Spark), validate schema before insert
-- Pseudo-code in SQL:
INSERT INTO job_postings_fact (
  job_id, job_title_short, salary_year_avg, 
  job_work_from_home, job_posted_date, job_location, 
  job_salary_currency, schema_version
)
SELECT 
  job_id, job_title_short, salary_year_avg,
  job_work_from_home, job_posted_date, job_location,
  job_salary_currency,
  '1.2.3' AS schema_version
FROM staging_job_postings
WHERE job_salary_currency IS NOT NULL  -- Fail loud: reject nulls
  AND job_posted_date IS NOT NULL;

-- Log the run
INSERT INTO pipeline_runs 
VALUES (
  '{{ run_id }}', 
  'job_postings_ingest', 
  '1.2.3',
  '1.2.3',
  CURRENT_TIMESTAMP(),
  'success',
  NULL
);
```

## Notes

- **Common mistake:** Deploying code changes without updating schema, then rerunning old code against new schema (or vice versa). Always version them together.
- **Idempotency patterns:** Use `MERGE` or `DELETE + INSERT` instead of raw `INSERT` to make reruns safe; partition by date so you can safely drop and rebuild one day's data.
- **Connects to:** Data contracts (defining what each pipeline outputs), observability (monitoring schema drift and row counts), and rollback strategies (keeping previous versions deployable).
- **Worth revisiting:** How to test transformations in CI/CD before merging, and how to structure your DAG so failed tasks can rerun without retriggering upstream dependencies.
- **Practical detail:** Store `run_id`, `version`, and `run_timestamp` in your fact tables or as Airflow context variables; this lets you query "which version produced this row?" months later.
