---
date: 2026-10-11
phase: pipelines
topic: Branching and conditional execution in workflows
---

# Branching and conditional execution in workflows

*Pipelines and orchestration*

## Concept

Branching and conditional execution allow workflows to take different paths based on data state, execution results, or external conditions. Instead of a linear sequence, tasks can skip, retry, or route to alternative handlers—critical when data quality varies, upstream dependencies fail, or business logic requires dynamic decisions. In orchestration frameworks (Airflow, dbt, Prefect), this is implemented via task dependencies with conditional operators, XCom (cross-task communication), or explicit branching DAG structures.

Without branching, failed tasks halt entire pipelines or force wasteful reruns of unaffected downstream work. Conditional logic also prevents nonsensical operations: you shouldn't transform job postings missing location data the same way as complete records, and you shouldn't trigger expensive alerts for every single anomaly—only actionable ones. This becomes essential at scale when pipelines span multiple domains and need to gracefully handle partial failures.

## Practice

**Problem:** Build a workflow that ingests job postings, but handles incomplete data gracefully. If >20% of today's records lack a salary, route them to a review queue instead of the main fact table. Otherwise, load normally and trigger downstream analytics.

```sql
-- Check data quality before loading
WITH daily_postings AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    CASE 
      WHEN salary_year_avg IS NULL THEN 'missing_salary'
      WHEN job_location IS NULL THEN 'missing_location'
      ELSE 'complete'
    END AS data_quality_flag
  FROM raw_job_postings
  WHERE job_posted_date = CURRENT_DATE
),
quality_summary AS (
  SELECT
    COUNT(*) AS total_records,
    COUNTIF(data_quality_flag = 'missing_salary') AS missing_salary_count,
    ROUND(COUNTIF(data_quality_flag = 'missing_salary') / COUNT(*), 2) AS salary_missing_pct
  FROM daily_postings
)
-- Branch: if missing_salary_pct > 0.20, load incomplete records to review table
SELECT 
  daily_postings.*,
  quality_summary.salary_missing_pct,
  CASE 
    WHEN quality_summary.salary_missing_pct > 0.20 THEN 'review_queue'
    ELSE 'job_postings_fact'
  END AS target_table
FROM daily_postings
CROSS JOIN quality_summary;

-- In orchestration (pseudo-Airflow):
-- if_complete = BranchPythonOperator(
--   task_id='check_quality',
--   python_callable=lambda: 'load_fact' if pct <= 0.20 else 'load_review'
-- )
-- load_fact >> analytics_downstream
-- load_review >> alert_data_team
```

## Notes

- **Avoid silent skips:** Always log why a branch was taken; failed tasks hiding in conditional logic are harder to debug than explicit failures.
- **XCom pollution:** Passing large datasets between tasks via XCom (Airflow) defeats the purpose of branching; use persistent staging tables instead, let SQL do the filtering.
- **Idempotency + branching:** Retryable workflows must produce the same outcome regardless of branch path taken; mark records with insertion timestamps and upsert patterns, don't assume linear ordering.
- **Adjacent: error handling & alerting:** Branching often pairs with try-catch logic and dead-letter queues; a review queue is a form of error containment, not a failure.
- **Revisit: dynamic task generation:** For many similar conditions (e.g., one branch per geography), consider `@task.dynamic` or mapped tasks instead of hardcoding branching logic.
