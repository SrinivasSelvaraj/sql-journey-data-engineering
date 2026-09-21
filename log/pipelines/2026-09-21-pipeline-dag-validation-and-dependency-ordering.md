---
date: 2026-09-21
phase: pipelines
topic: Pipeline DAG validation and dependency ordering
---

# Pipeline DAG validation and dependency ordering

*Pipelines and orchestration*

## Concept

A DAG (directed acyclic graph) is the structural spine of any orchestrated pipeline—it defines which tasks run, in what order, and what depends on what. Validation ensures your DAG is acyclic (no circular dependencies), complete (no orphaned tasks), and executable (all upstream dependencies exist before downstream tasks run). Without it, you get runtime failures that cascade unpredictably: a task runs before its input is ready, data gets corrupted, or the orchestrator deadlocks trying to resolve impossible ordering.

DAG validation happens at parse time (does the graph structure make sense?) and at runtime (are all upstream tasks actually complete?). The stakes are high in data pipelines because a broken dependency can silently produce stale or partial datasets. A job_postings_fact table built without waiting for source data to land will join against yesterday's records, corrupting your fact table irreversibly.

## Practice

**Problem:** You have three tasks: `extract_job_postings` → `clean_salaries` → `load_fact_table`. The `clean_salaries` task depends on output from `extract_job_postings`, but you forgot to declare it. The orchestrator runs both in parallel, and `clean_salaries` fails because the source table doesn't exist yet. How do you make this dependency explicit and validate it?

```sql
-- Pseudo-code for DAG definition with explicit dependencies
-- (Airflow/dbt example pattern)

-- Task 1: Extract raw data
CREATE TABLE raw_job_postings AS
SELECT * FROM external_source;

-- Task 2: Clean and enrich (depends on Task 1)
-- Explicit dependency: this task waits for raw_job_postings to exist
CREATE TABLE cleaned_job_postings AS
SELECT 
  job_id,
  job_title_short,
  CAST(salary_year_avg AS NUMERIC) AS salary_year_avg,
  LOWER(TRIM(job_location)) AS job_location,
  job_posted_date
FROM raw_job_postings
WHERE salary_year_avg IS NOT NULL
  AND job_posted_date >= CURRENT_DATE - INTERVAL '30 days';

-- Task 3: Load fact table (depends on Task 2)
CREATE TABLE job_postings_fact AS
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  CASE WHEN job_location ILIKE '%remote%' THEN TRUE ELSE FALSE END AS job_work_from_home,
  job_posted_date,
  job_location
FROM cleaned_job_postings;

-- Validation check: confirm all upstream tables exist before loading fact
-- Run this as a pre-flight check in your orchestrator
SELECT COUNT(*) FROM information_schema.tables 
WHERE table_name IN ('raw_job_postings', 'cleaned_job_postings');
```

## Notes

- **Circular dependency trap:** If Task A depends on B and B depends on A (directly or indirectly), the DAG is invalid. Orchestrators like Airflow catch this at parse time, but custom code won't—validate with a cycle-detection algorithm.
- **Missing dependency vs. loose coupling:** Declaring dependencies tightly is safer than relying on naming conventions or assumed execution order. Explicit beats implicit.
- **Sensor vs. hard dependency:** Use sensors (wait for external event/file) only when necessary; hard dependencies (upstream task completion) are simpler and more debuggable.
- **Idempotency and retries:** Even with perfect DAG ordering, tasks must be idempotent so failed retries don't corrupt downstream data. A re-run of `load_fact_table` should produce the same result.
- **Connects to:** error handling strategies (fail loudly), data quality checks (validate outputs before downstream consumption), and observability (log which tasks ran, in what order, and how long each took).
