---
date: 2026-10-29
phase: pipelines
topic: Catchup and backfill scheduling modes
---

# Catchup and backfill scheduling modes

*Pipelines and orchestration*

## Concept

Catchup and backfill scheduling modes determine how an orchestrator handles missed or incomplete data intervals when a pipeline restarts. **Catchup mode** automatically reruns all missed DAG runs between the last successful execution and the present, while **backfill mode** is a manual, explicit request to reprocess a specific historical date range. Without proper scheduling modes, you either lose data (gaps in your warehouse) or wastefully reprocess intervals that already completed successfully.

The distinction matters most when pipelines fail, infrastructure restarts, or business requirements change retroactively. A daily job that failed for three days needs catchup to fill those gaps; a schema change requiring recalculation of the past six months needs a deliberate backfill. Confusing the two leads to either silent data incompleteness or runaway compute costs—both dangerous in analytics pipelines where stakeholders trust the numbers without verification.

## Practice

**Problem:** Your `job_postings_fact` table loads job postings daily at 02:00 UTC. On Tuesday, the DAG failed due to a database connection timeout. When restarted Wednesday morning, you need to ensure Monday's, Tuesday's, and Wednesday's data all load correctly without manually triggering each day.

```sql
-- Solution: Configure Airflow DAG with catchup=True and backfill_window
from airflow import DAG
from airflow.operators.postgres_operator import PostgresOperator
from datetime import datetime, timedelta

default_args = {
    'start_date': datetime(2024, 1, 08),
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'load_job_postings',
    default_args=default_args,
    schedule_interval='0 2 * * *',  -- Daily at 02:00 UTC
    catchup=True,  -- Automatically run missed intervals
    max_active_runs=3,  -- Prevent resource explosion
)

load_postings = PostgresOperator(
    task_id='insert_daily_postings',
    sql='''
        INSERT INTO job_postings_fact 
        (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
        SELECT 
            job_id, job_title_short, salary_year_avg, job_work_from_home, 
            job_posted_date, job_location
        FROM raw.job_postings_staging
        WHERE DATE(job_posted_date) = '{{ ds }}'  -- Logical date of this run
            AND load_timestamp > (SELECT MAX(load_timestamp) FROM job_postings_fact 
                                   WHERE job_posted_date = '{{ ds }}')
        ON CONFLICT (job_id) DO UPDATE SET 
            salary_year_avg = EXCLUDED.salary_year_avg,
            job_work_from_home = EXCLUDED.job_work_from_home;
    ''',
    dag=dag,
)
```

For a deliberate backfill (e.g., correcting Q3 data after a schema fix), use the Airflow CLI: `airflow backfill load_job_postings --start-date 2024-07-01 --end-date 2024-09-30`

## Notes

- **Catchup gotcha**: Enabling `catchup=True` without `max_active_runs` can trigger hundreds of concurrent tasks, overwhelming your database and warehouse. Always set a reasonable ceiling.
- **Idempotency is non-negotiable**: Every task must produce identical results when run multiple times on the same interval—use `ON CONFLICT` (Postgres) or `MERGE` (Snowflake) to handle duplicate inserts gracefully.
- **Logical date vs. execution date**: The `{{ ds }}` template variable represents the *logical* date (data date), not when the DAG actually ran. This separation is critical for correct backfill semantics.
- **Monitor backfill scope**: A backfill spanning 12 months of daily jobs can consume significant compute. Validate the date range and expected volume before execution in production.
- **Adjacent: idempotent design, incremental loading, data quality gates**—these concepts work together to make catchup/backfill safe and trustworthy.
