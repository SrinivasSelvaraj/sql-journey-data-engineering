---
date: 2026-09-22
phase: pipelines
topic: Branching operators and dynamic task generation
---

# Branching operators and dynamic task generation

*Pipelines and orchestration*

## Concept

Branching operators and dynamic task generation allow workflows to split execution paths based on runtime conditions and to create task instances programmatically rather than hardcoding them. In orchestration frameworks like Airflow, branching (via `@task.branch` or similar) evaluates a condition and returns the task ID(s) to execute next, while dynamic task generation (via `expand()` or map operations) creates parallel tasks from a list computed during runtime—such as one task per partition or per data quality check result.

These patterns matter because real pipelines encounter conditional logic: "if the data quality check fails, trigger an alert task instead of loading to production"; "if we have 50 new customers, spawn 50 separate refresh tasks, not one monolithic loop." Without them, you either hardcode all possible branches (brittle, unmaintainable) or use a single sequential task that hides failures and obscures what actually ran.

Breaking without these patterns manifests as opaque failures ("the DAG ran but I don't know which branch executed"), wasted resources (always running all tasks), or fragile recovery (rerunning a monolithic task reruns everything, not just the failure point).

## Practice

**Problem:** You need to load job postings daily, but the logic differs by work-from-home status. Remote jobs get written to a Snowflake table with special indexing; on-site jobs go to a different table. Additionally, you must dynamically generate one data quality check task per job location in the dataset, and skip downstream loading if *any* quality check fails.

```sql
-- Dynamic task generation: get distinct locations to check
SELECT DISTINCT job_location 
FROM job_postings_fact 
WHERE job_posted_date = CURRENT_DATE();

-- Branching logic: separate load paths by work_from_home
-- In Airflow pseudo-code pattern:
-- @task.branch
-- def route_by_work_location():
--   if count(job_work_from_home = TRUE) > threshold:
--     return 'load_remote_jobs'
--   else:
--     return 'load_onsite_jobs'

-- Load remote jobs (separate table with different distribution key)
INSERT INTO job_postings_remote (job_id, job_title_short, salary_year_avg, job_posted_date)
SELECT job_id, job_title_short, salary_year_avg, job_posted_date
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE()
  AND job_work_from_home = TRUE;

-- Load on-site jobs (separate table)
INSERT INTO job_postings_onsite (job_id, job_title_short, salary_year_avg, job_posted_date)
SELECT job_id, job_title_short, salary_year_avg, job_posted_date
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE()
  AND job_work_from_home = FALSE;

-- QA check template (one instance per location)
SELECT 
  '{{ location }}' AS location,
  COUNT(*) AS row_count,
  COUNT(DISTINCT job_id) AS distinct_jobs,
  MIN(salary_year_avg) AS min_salary,
  MAX(salary_year_avg) AS max_salary,
  CASE 
    WHEN COUNT(*) = 0 THEN 'FAIL: no rows'
    WHEN COUNT(DISTINCT job_id) < COUNT(*) * 0.95 THEN 'FAIL: duplicates'
    WHEN MIN(salary_year_avg) IS NULL THEN 'FAIL: null salary'
    ELSE 'PASS'
  END AS qc_status
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE()
  AND job_location = '{{ location }}';
```

## Notes

- **Mistake: over-branching.** Don't create a branch for every tiny conditional; reserve branching for genuinely different downstream work (different table, different SLA, alert vs. load). Use task parameters for simple flag logic.
- **Mistake: dynamic generation without limits.** If you generate one task per row (1M rows = 1M tasks), the scheduler chokes. Use aggregation, bucketing, or batching (e.g., "one task per 10K rows") to keep task count reasonable (aim for <1000 per DAG run).
- **Connector to XComs and data passing.** Branching decisions often depend on intermediate results (row counts, data freshness checks). Use XCom to pass these; don't query the database twice.
- **Connector to idempotency and rerun safety.** When a branch reruns, ensure its SQL is idempotent (use upserts or truncate-then-load, not append). Dynamic tasks must be deterministic—same input → same task list—or reruns create orphaned tasks.
- **Worth revisiting: conditional operators vs. mapped tasks.** Use `@task.branch` for "execute A *or* B"; use `.expand()` for "execute A for each item in list." They solve different problems and can compose.
