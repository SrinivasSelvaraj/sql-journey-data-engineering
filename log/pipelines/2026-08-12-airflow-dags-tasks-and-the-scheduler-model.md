---
date: 2026-08-12
phase: pipelines
topic: Airflow: DAGs, tasks and the scheduler model
---

# Airflow: DAGs, tasks and the scheduler model

*Pipelines and orchestration*

## Concept

A DAG (Directed Acyclic Graph) in Airflow is a declarative blueprint of your data pipeline—a set of tasks and their dependencies that the scheduler executes on a fixed cadence. Each task is an atomic unit of work (a Python function, SQL query, or bash command), and edges between tasks define execution order. The scheduler continuously monitors DAGs, triggers runs at specified intervals, retries failed tasks according to policy, and provides the execution layer that separates *what you want to do* from *when and how it runs*.

This model matters because it forces idempotency and explicit dependencies: you cannot accidentally skip a transformation step or run tasks out of order. Without it, you resort to cron jobs strung together with brittle shell scripts, where a single failure cascades invisibly and reruns corrupt intermediate state. Airflow's scheduler catches failures early, logs them prominently, and reruns only the failed task and its dependents—not the entire pipeline.

## Practice

**Problem:** You have a `job_postings_fact` table updated daily. You need to:
1. Extract rows posted in the last 7 days
2. Enrich salary data (impute nulls with role median)
3. Flag remote-eligible jobs
4. Write results to a reporting table
5. Alert if no rows processed (fail loudly)

**Solution:**

```sql
-- Task 1: Extract recent postings
CREATE TEMP TABLE recent_postings AS
SELECT * FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7 days';

-- Task 2: Enrich and flag
WITH enriched AS (
  SELECT
    job_id,
    job_title_short,
    COALESCE(salary_year_avg, 
      PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) 
      OVER (PARTITION BY job_title_short)) AS salary_year_avg_imputed,
    job_work_from_home,
    job_posted_date,
    job_location,
    CASE WHEN job_work_from_home = TRUE THEN 1 ELSE 0 END AS is_remote_eligible
  FROM recent_postings
)
-- Task 3: Insert to reporting table
INSERT INTO job_postings_enriched
SELECT * FROM enriched
WHERE (SELECT COUNT(*) FROM enriched) > 0;

-- Task 4: Fail loudly if empty
SELECT CASE 
  WHEN COUNT(*) = 0 
  THEN RAISE_ERROR('No rows processed. Check job_postings_fact for recent data.')
  ELSE COUNT(*)
END AS row_count
FROM job_postings_enriched
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7 days';
```

## Notes

- **Idempotency is non-negotiable:** tasks must produce identical results when run multiple times with the same inputs; parameterize by `ds` (execution date) not `now()`.
- **Sensor tasks** (waiting for external data) and **branching** (conditional task paths) extend the basic DAG model; learn these before writing production pipelines.
- **Task dependencies via `>>` and `<<` operators** are clearer than XCom passing; avoid premature optimization of data flow between tasks.
- **Backfills rerun historical ranges** and expose bugs hidden by incremental runs; always test against a small backfill window first.
- Related: task pools (concurrency limits), SLAs (alerting on deadline miss), dynamic task mapping (fan-out/fan-in patterns).
