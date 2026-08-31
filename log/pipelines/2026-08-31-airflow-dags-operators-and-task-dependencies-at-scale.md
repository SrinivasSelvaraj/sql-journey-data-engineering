---
date: 2026-08-31
phase: pipelines
topic: Airflow: DAGs, operators and task dependencies at scale
---

# Airflow: DAGs, operators and task dependencies at scale

*Pipelines and orchestration*

## Concept

A DAG (Directed Acyclic Graph) in Airflow represents a workflow as a collection of tasks with explicit dependencies. Operators define *what* work gets done (PythonOperator, BashOperator, SqlOperator, etc.), while task dependencies (`task_a >> task_b`) define *when* work runs. At scale—hundreds of tasks, multiple teams, varied failure modes—this clarity becomes critical: ambiguous execution order causes cascading failures, silent data corruption, and impossible debugging. Airflow enforces your dependency graph visually and programmatically, so missing a link between tasks becomes obvious before production breaks.

Without explicit task dependencies, parallel tasks run in undefined order, making retries unpredictable and root-cause analysis nearly impossible. A single missing dependency can cause a downstream task to consume stale data, invalidating weeks of results. Airflow's task retry logic, backfill capability, and monitoring only work reliably when the DAG is acyclic and complete—implicit or circular dependencies silently fail or hang indefinitely.

## Practice

**Problem:** Load job postings into a data warehouse with these requirements:
- Extract raw job postings from an API endpoint
- Validate that salary_year_avg is positive and job_posted_date is recent
- Deduplicate by job_id, keeping the latest posted_date
- Merge into the fact table, updating existing records and inserting new ones
- Alert on-call if the load inserts fewer than 100 rows (indicating a problem upstream)

```sql
-- Task 1: Stage raw data (extract via API, load to staging)
CREATE TEMP TABLE job_postings_raw AS
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM external_api_endpoint
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 7 DAY;

-- Task 2: Validate and deduplicate
CREATE TEMP TABLE job_postings_cleaned AS
SELECT DISTINCT ON (job_id) 
  job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM job_postings_raw
WHERE salary_year_avg > 0 
  AND job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY
ORDER BY job_id, job_posted_date DESC;

-- Task 3: Merge into fact table
MERGE INTO job_postings_fact AS target
USING job_postings_cleaned AS source
ON target.job_id = source.job_id
WHEN MATCHED AND source.job_posted_date > target.job_posted_date THEN
  UPDATE SET job_title_short = source.job_title_short,
             salary_year_avg = source.salary_year_avg,
             job_work_from_home = source.job_work_from_home,
             job_posted_date = source.job_posted_date,
             job_location = source.job_location
WHEN NOT MATCHED THEN
  INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
  VALUES (source.job_id, source.job_title_short, source.salary_year_avg, 
          source.job_work_from_home, source.job_posted_date, source.job_location);

-- Task 4: Validate row count and alert if anomaly detected
SELECT CASE 
  WHEN COUNT(*) < 100 THEN 'ALERT: Fewer than 100 rows inserted. Check upstream data source.'
  ELSE 'Load successful: ' || COUNT(*) || ' rows processed.'
END AS load_status
FROM job_postings_cleaned;
```

In Airflow: `extract_task >> validate_task >> merge_task >> alert_task`. Each task depends on the previous one succeeding; if validate_task fails, merge and alert never run, preventing corrupt data from entering the fact table.

## Notes

- **Circular dependencies are fatal:** `task_a >> task_b >> task_a` will fail silently or hang. Use Airflow's graph visualizer to catch these before deployment.
- **Retry logic requires isolation:** Each task must be independently rerunnable. If a task has side effects (e.g., incomplete deletes), retries compound damage. Keep staging tables task-scoped and use transactions.
- **Sensor tasks are dependency linchpins:** Use `ExternalTaskSensor` and file sensors to wait for upstream dependencies outside your DAG, especially in multi-team environments where you don't control the source system.
- **Backfill and time-travel depend on idempotent tasks:** Design each task so running it twice with the same `execution_date` produces the same result. Parameterize by `{{ ds }}` or `{{ execution_date }}` to avoid reprocessing overlapping data.
- **Monitor task SLAs aggressively:** Set `sla` timedeltas on critical tasks; Airflow will alert you if tasks miss their window, catching silent
