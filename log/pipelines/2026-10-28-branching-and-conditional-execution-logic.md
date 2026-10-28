---
date: 2026-10-28
phase: pipelines
topic: Branching and conditional execution logic
---

# Branching and conditional execution logic

*Pipelines and orchestration*

## Concept

Branching and conditional execution logic in data pipelines determines *which tasks run, when, and under what conditions*. This includes runtime decisions based on data quality checks, upstream task success/failure, row counts, or data values—not just static DAG structures. Without it, pipelines either run everything blindly (masking failures) or halt entirely on first error, leaving downstream consumers without partial results or clear failure signals.

In orchestration tools like Airflow or dbt, this manifests as task dependencies with conditions, sensor operators, and branching operators that inspect intermediate results before deciding next steps. A salary validation job might branch: if 95%+ of records pass, proceed to mart layer; if not, trigger an alert and skip publication. This prevents silent data quality degradation and enables pipelines to "fail loudly" (alert immediately) while remaining "safe to rerun" (idempotent, no cascading side effects).

Without conditional logic, you lose observability—you cannot distinguish between "the data arrived but failed validation" and "the upstream job crashed." You also force binary outcomes (all-or-nothing) when real pipelines need graduated responses.

## Practice

**Problem:** Build a pipeline that loads `job_postings_fact`, validates salary data completeness, and branches accordingly. If ≥80% of records have non-null `salary_year_avg`, merge into the production mart; otherwise, log the failure, quarantine the batch, and notify the data team.

```sql
-- Step 1: Load and calculate completeness
WITH incoming_data AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location
  FROM staging.job_postings_raw
  WHERE job_posted_date = CURRENT_DATE
),

quality_check AS (
  SELECT
    COUNT(*) AS total_records,
    COUNT(salary_year_avg) AS salary_non_null,
    ROUND(100.0 * COUNT(salary_year_avg) / COUNT(*), 2) AS completeness_pct
  FROM incoming_data
)

-- Step 2: Conditional insert based on quality threshold
INSERT INTO 
  CASE 
    WHEN (SELECT completeness_pct FROM quality_check) >= 80 THEN
      production.job_postings_fact
    ELSE
      quarantine.job_postings_failed_qa
  END
SELECT * FROM incoming_data
WHERE (SELECT completeness_pct FROM quality_check) >= 80;

-- Step 3: Log quality result (in Airflow/dbt, handle via conditional task)
INSERT INTO audit.pipeline_quality_log (
  pipeline_name, check_date, total_records, completeness_pct, status
)
SELECT
  'job_postings_daily',
  CURRENT_DATE,
  total_records,
  completeness_pct,
  CASE WHEN completeness_pct >= 80 THEN 'PASSED' ELSE 'FAILED' END
FROM quality_check;
```

## Notes

- **Branch at the orchestrator level, not in SQL**: Use Airflow's `BranchPythonOperator` or dbt's `execute` meta-property to inspect upstream results and skip downstream tasks. SQL should contain the *logic* (which rows qualify), not the *control flow*.

- **Idempotency is critical**: If a job reruns after failure, conditional logic must not duplicate work or leave partial state. Use upserts with unique keys or write to date-partitioned quarantine tables.

- **Adjacent topic—sensors and polling**: Sensors (e.g., `FileSensor`, `ExternalTaskSensor`) implement conditional wait logic—don't proceed until a file lands or upstream DAG completes. They bridge orchestration and conditional execution.

- **Common mistake—silent branch failures**: A branch that selects no tasks is not the same as a branch that fails. Log *why* a condition failed (row count, null %, schema mismatch) to enable fast debugging.

- **Revisit: data quality frameworks** (Great Expectations, dbt tests) pair naturally with branching—test results feed conditional logic, and failed checks trigger alerts and quarantine flows rather than propagating bad data downstream.
