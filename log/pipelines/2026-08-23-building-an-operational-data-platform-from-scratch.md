---
date: 2026-08-23
phase: pipelines
topic: Building an operational data platform from scratch
---

# Building an operational data platform from scratch

*Pipelines and orchestration*

## Concept

A pipeline that "fails loudly, reruns safely, and explains itself" means three things working together: first, errors must surface immediately and unmistakably rather than silently producing wrong data; second, the pipeline must be idempotent—rerunning it on the same input produces the same output without duplication or corruption; third, every run must leave an audit trail (logs, data lineage, run metrics) so you can explain what happened and why.

This matters because silent data quality issues are far more damaging than loud failures. A job posting ingestion that silently deduplicates wrong records, a transformation that reruns and doubles counts, or a load that crashes halfway without rollback will corrupt dashboards and reports that decision-makers trust. Without idempotency, you either avoid reruns (and live with partial failures) or spend hours cleaning up duplicates. Without observability, you debug blind—was the API rate-limited? Did the schema change? Did a timezone calculation fail halfway through?

Operationally, this means designing pipelines around explicit state management: using surrogate keys and `MERGE` logic instead of appends, tracking run IDs in every table, logging schema assumptions, and instrumenting data volumes at each step. It's the difference between a pipeline you trust at 2 AM and one that wakes you up at 2 AM.

## Practice

**Problem:** The job_postings_fact table is appended to daily. When the orchestrator reruns yesterday's load, duplicates accumulate. Remote-work filtering logic occasionally crashes mid-run, leaving the table in an inconsistent state. Downstream reports show conflicting salary counts.

**Solution:**

```sql
-- Idempotent merge with run tracking and validation
CREATE TABLE job_postings_fact (
  job_id INT,
  job_title_short VARCHAR(100),
  salary_year_avg DECIMAL(10,2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(100),
  dbt_run_id VARCHAR(50),  -- unique identifier for each pipeline run
  loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (job_id, dbt_run_id)
);

-- Idempotent load: delete then insert for this run only
DELETE FROM job_postings_fact 
WHERE dbt_run_id = '{{ run_id }}';

INSERT INTO job_postings_fact 
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  COALESCE(job_work_from_home, FALSE) AS job_work_from_home,
  job_posted_date,
  job_location,
  '{{ run_id }}' AS dbt_run_id,
  CURRENT_TIMESTAMP
FROM {{ source('raw', 'job_postings_api') }}
WHERE job_posted_date = '{{ ds }}'
  AND salary_year_avg IS NOT NULL  -- fail loudly on data contract breach
  AND job_location IS NOT NULL;

-- Validation: log row counts for explainability
INSERT INTO pipeline_audit_log (table_name, run_id, row_count, check_name, status)
SELECT 
  'job_postings_fact',
  '{{ run_id }}',
  COUNT(*),
  'row_count_inserted',
  CASE WHEN COUNT(*) > 0 THEN 'passed' ELSE 'failed' END
FROM job_postings_fact
WHERE dbt_run_id = '{{ run_id }}';
```

## Notes

- **Idempotency trap:** Using `INSERT OR REPLACE` with composite keys works until it doesn't—prefer explicit `DELETE THEN INSERT` or `MERGE` to stay in control of what gets touched.
- **Run IDs are non-negotiable:** Without them, you cannot isolate which execution caused corruption. Use a `dbt_run_id` or equivalent in every fact table; this enables safe reruns and forensics.
- **Observability connects here:** Data contracts (schema validation, nullability rules), data lineage (source → transform → load), and SLAs (row count thresholds) are all ways pipelines "explain themselves."
- **Revisit surrogate keys:** If your source has no natural key, generate one deterministically (hash of business key) so reruns land on the same row.
- **Error handling and retries:** "Fail loudly" means raising exceptions for data anomalies, not catching and logging. Let the orchestrator (Airflow, Dagster) retry; your job is to make retries safe.
