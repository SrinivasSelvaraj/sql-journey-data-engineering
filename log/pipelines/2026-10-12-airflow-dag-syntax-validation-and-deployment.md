---
date: 2026-10-12
phase: pipelines
topic: Airflow DAG: syntax, validation and deployment
---

# Airflow DAG: syntax, validation and deployment

*Pipelines and orchestration*

## Concept

A DAG (Directed Acyclic Graph) in Airflow is a collection of tasks with explicit dependencies that define execution order and parallelism. Each task is an atomic unit of work (PythonOperator, BashOperator, etc.), and edges represent dependencies—Task A must complete before Task B starts. Validation ensures your DAG has no cycles, all referenced variables exist, and operators are correctly configured; deployment moves validated code into Airflow's scheduler so it can be parsed, scheduled, and executed on cadence.

DAGs matter because orchestration failures are expensive: a broken dependency can cause data loss, a syntax error can prevent the entire pipeline from running, and an invalid schedule can create gaps in coverage. Without validation before deployment, you discover errors at runtime when operators fail, wasting compute and delaying data. Airflow's validation layer catches issues early—circular dependencies, missing imports, undefined XCom references, and operator misconfiguration—so failures are loud and immediate, not silent and downstream.

A properly written, validated, and deployed DAG is self-documenting: task names, doc strings, and dependency graphs explain the workflow; retries and error handlers make recovery automatic; and alerting on failure surfaces problems fast. Without this discipline, pipelines become fragile, hard to debug, and unreliable.

## Practice

**Problem:** You need to build a daily pipeline that extracts new job postings from an API, validates salary data, and loads them into `job_postings_fact`. The pipeline should retry on transient failure, skip rows with missing salaries, and alert on critical errors. Write the DAG structure and a sample extraction task.

```python
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from airflow.utils.dates import days_ago
from datetime import datetime, timedelta
import logging

# Define DAG
dag = DAG(
    dag_id='job_postings_etl',
    description='Extract, validate, and load job postings daily',
    schedule_interval='0 2 * * *',  # 2 AM UTC daily
    start_date=days_ago(1),
    catchup=False,
    default_args={
        'retries': 2,
        'retry_delay': timedelta(minutes=5),
        'email_on_failure': True,
        'email': ['data-team@example.com']
    },
    tags=['jobs', 'daily'],
)

def extract_job_postings(**context):
    """Fetch new job postings from API, return count."""
    import requests
    response = requests.get('https://api.example.com/jobs', params={'limit': 1000})
    response.raise_for_status()
    data = response.json()
    logging.info(f"Extracted {len(data)} job postings")
    context['task_instance'].xcom_push(key='record_count', value=len(data))
    return len(data)

def validate_and_load(**context):
    """Load to job_postings_fact, skip nulls in salary_year_avg."""
    import pandas as pd
    record_count = context['task_instance'].xcom_pull(
        task_ids='extract', key='record_count'
    )
    logging.info(f"Validation starting for {record_count} records")
    # Pseudo-code: load, filter WHERE salary_year_avg IS NOT NULL, insert
    return {'loaded': record_count, 'skipped': 0}

# Tasks
extract_task = PythonOperator(
    task_id='extract',
    python_callable=extract_job_postings,
    dag=dag,
)

validate_task = PythonOperator(
    task_id='validate_and_load',
    python_callable=validate_and_load,
    dag=dag,
)

dbt_test = BashOperator(
    task_id='dbt_test',
    bash_command='dbt test --select job_postings_fact',
    dag=dag,
)

# Dependencies: extract → validate → test
extract_task >> validate_task >> dbt_test
```

## Notes

- **Validation before deploy:** Use `airflow dbt validate` or `python -m py_compile` locally; Airflow will parse your DAG on upload, but linting early saves iterations. Check for undefined `xcom_pull` keys, missing imports, and circular edges.
- **Retries + idempotency:** Always design tasks to be replayable—insert with conflict handling, use timestamps not sequence IDs, avoid side-effects. `retries` and `retry_delay` make transient failures forgiving; without idempotency, retries cause duplicates or corruption.
- **XCom and task communication:** Passing data via XCom (task instance context) couples tasks loosely; but XCom keys must match exactly between push/pull. Document keys or use constants to avoid silent failures.
- **Schedule and backfill:** `schedule_interval` controls cadence; `catchup=False` skips backfill on
