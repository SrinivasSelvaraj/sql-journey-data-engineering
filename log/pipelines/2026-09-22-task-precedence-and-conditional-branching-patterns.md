---
date: 2026-09-22
phase: pipelines
topic: Task precedence and conditional branching patterns
---

# Task precedence and conditional branching patterns

*Pipelines and orchestration*

## Concept

Task precedence defines the execution order of pipeline steps and ensures downstream tasks only run when their dependencies succeed. Conditional branching allows tasks to follow different paths based on data conditions or previous task outcomes, enabling intelligent error handling and adaptive workflows. Together, they prevent cascading failures (where a broken task silently poisons downstream results) and make pipelines explainable—you can trace why a task ran, skipped, or failed.

Without clear precedence, tasks may run in unpredictable order or in parallel when they shouldn't, causing race conditions on shared resources or dependencies. Without branching logic, pipelines either fail hard on any anomaly or swallow errors silently. A typical failure mode: a fact table load succeeds but loads zero rows, and downstream aggregations happily compute from empty data, producing misleading metrics that go unnoticed for days.

Orchestration tools (Airflow, dbt, Prefect) enforce precedence through DAGs and offer conditional operators to branch on task state or data quality checks. The pattern is: declare what must happen *before* what, and what to do *if* things go wrong.

## Practice

**Problem:** You need to load `job_postings_fact` from a staging table, but only proceed with downstream salary analysis if at least 1000 rows with non-null `salary_year_avg` were loaded in the current run. If that threshold is not met, log a warning and skip aggregation rather than computing on sparse data.

```sql
-- Step 1: Load fact table and check row count
WITH staging AS (
  SELECT * FROM stg_job_postings
  WHERE job_posted_date = CURRENT_DATE
),
validation AS (
  SELECT 
    COUNT(*) as total_rows,
    COUNT(salary_year_avg) as salary_rows,
    CASE 
      WHEN COUNT(salary_year_avg) >= 1000 THEN 'PASS'
      ELSE 'FAIL'
    END as quality_gate
  FROM staging
)
INSERT INTO job_postings_fact
SELECT 
  job_id, job_title_short, salary_year_avg, job_work_from_home, 
  job_posted_date, job_location
FROM staging
WHERE (SELECT quality_gate FROM validation) = 'PASS';

-- Step 2: Conditional downstream task (pseudocode for orchestrator)
-- IF (SELECT quality_gate FROM validation) = 'PASS' THEN
--   INSERT INTO salary_analysis_summary (select aggregates from job_postings_fact)
-- ELSE
--   RAISE WARNING 'Salary data insufficient; skipping analysis'
-- END IF
```

The validation query runs first, stores its result, and the orchestrator checks it before deciding whether the aggregation task executes. This "fail loud, skip gracefully" pattern prevents silent data quality issues.

## Notes

- **Precedence mistake:** Assuming a tool will infer order from column names or timestamps; always *declare* dependencies explicitly (e.g., `task_b.set_upstream(task_a)` in Airflow).
- **Branching mistake:** Using only CASE statements in SQL without orchestrator-level branching; the SQL completes either way, wasting compute and hiding intent. Use orchestrator conditionals to *skip* tasks entirely.
- **Related:** data quality gates (great Sentinel checks before branching), idempotency (tasks must be safe to rerun after a branch is taken), and observability (log branch decisions so audit trails show why paths were taken).
- **Testing edge:** Test the failure path explicitly—mock a failed upstream task or data quality gate and verify the skip/retry logic works, not just the happy path.
- **Revisit:** Combine with circuit-breaker patterns (halt the whole pipeline if a critical check fails) and backpressure logic (pause downstream if upstream is slow).
