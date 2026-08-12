---
date: 2026-08-12
phase: pipelines
topic: Airflow: execution date, catchup and the off-by-one trap
---

# Airflow: execution date, catchup and the off-by-one trap

*Pipelines and orchestration*

## Concept

Airflow's `execution_date` is the *start* of the data interval a DAG run processes, not when the task executes. A DAG scheduled daily at 2024-01-02 has `execution_date=2024-01-01`, meaning it processes data from 2024-01-01. This off-by-one relationship trips engineers who expect `execution_date` to match wall-clock time or confuse it with `run_date` (when Airflow actually schedules the run).

The `catchup` parameter controls whether Airflow backfills missed runs. With `catchup=True`, a paused DAG scheduled daily that resumes after a week will spawn seven runs with consecutive `execution_date` values. Without catchup, only the current interval runs. This matters because backfill is often necessary for data consistency—you cannot skip days in a time-series fact table—but uncontrolled catchup can overwhelm your scheduler or database with concurrent historical jobs.

The trap: filtering on `execution_date` directly in your pipeline logic. If you query `WHERE job_posted_date >= {{ execution_date }}`, you're implicitly assuming UTC midnight boundaries and excluding data posted between midnight and query time. Worse, during catchup, a single logical DAG run (say, 2024-01-01) can execute days later, making timestamps in logs confusing. You must separate *when the code runs* from *what data interval it processes*.

## Practice

**Problem:** You have a fact table `job_postings_fact` with daily inserts keyed by `job_posted_date`. Your DAG runs daily at 03:00 UTC and should load all jobs posted in the previous calendar day (e.g., run on 2024-01-02 loads jobs from 2024-01-01). You've set `schedule_interval='0 3 * * *'` and `catchup=True`. Write the SQL filter that correctly handles the execution_date without off-by-one errors.

```sql
-- Airflow 2.x with execution_date={{ ds }} (YYYY-MM-DD string)
-- {{ ds }} is the execution_date in YYYY-MM-DD format
INSERT INTO job_postings_fact (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM staging_jobs
WHERE job_posted_date = '{{ ds }}'::DATE
  AND job_posted_date IS NOT NULL
ORDER BY job_id;
```

The key: `{{ ds }}` is the execution_date as a string (e.g., `2024-01-01`), and you query `WHERE job_posted_date = '{{ ds }}'`, not `>=` or `>`. This ensures a single day's load per run, survives catchup cleanly, and remains idempotent.

## Notes

- **Mistake:** Using `>= execution_date AND < execution_date + 1 day` in timezone-naive environments; always cast or use `ds` macro which is already a DATE string in UTC.
- **Mistake:** Setting `catchup=False` to "avoid reprocessing," then wondering why historical gaps exist; catchup is your safety net for backfill, use it with `max_active_runs` to throttle instead.
- **Adjacent topic:** `data_interval_start` and `data_interval_end` (Airflow 2.2+) are the explicit boundaries; prefer these over `execution_date` in new DAGs for clarity.
- **Adjacent topic:** Idempotency and upserts; even with correct `execution_date` filtering, your INSERT/MERGE logic must handle reruns (e.g., via `INSERT … ON CONFLICT DO UPDATE`).
- **Revisit:** How `schedule_interval` and timezone settings (`default_timezone` in `airflow.cfg`) affect when `execution_date` rolls over; a misconfigured timezone can shift all your data intervals by hours.
