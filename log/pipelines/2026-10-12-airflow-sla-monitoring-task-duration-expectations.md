---
date: 2026-10-12
phase: pipelines
topic: Airflow SLA monitoring: task duration expectations
---

# Airflow SLA monitoring: task duration expectations

*Pipelines and orchestration*

## Concept

SLA (Service Level Agreement) monitoring in Airflow enforces task duration expectations by setting maximum acceptable execution times. When a task exceeds its `sla_seconds` parameter, Airflow triggers SLA miss callbacks and can alert you before the DAG completes—critical for catching slow tasks that might cascade failures downstream. This differs from task timeouts: an SLA miss doesn't kill the task, it signals degradation; a timeout actively terminates execution.

SLA monitoring matters most in data pipelines where downstream consumers expect fresh data by specific times. A job that normally runs in 2 minutes but takes 10 minutes today still produces results, but might violate business SLAs if dashboards refresh at 9 AM sharp. Without SLA definitions, you only notice problems retrospectively—after users report stale data.

Without explicit SLA tracking, slow tasks hide in logs. Your pipeline might be technically "passing" (no errors) while systematically violating latency contracts, and you won't know until reporting deadlines are missed.

## Practice

**Problem:** Your `extract_job_postings` task typically completes in 90 seconds but occasionally takes 8+ minutes, causing your downstream `calculate_salary_insights` to miss its 10 AM dashboard refresh window. Set up SLA monitoring and a callback that logs the miss.

```python
from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime, timedelta

def sla_miss_callback(context):
    task = context['task']
    dag_run = context['dag_run']
    print(f"⚠️ SLA MISS: {task.task_id} exceeded {task.sla} on {dag_run.execution_date}")

def extract_job_postings():
    # SELECT * FROM raw_job_postings WHERE ingested_date = CURRENT_DATE
    pass

with DAG(
    'job_analytics_pipeline',
    start_date=datetime(2024, 1, 1),
    schedule_interval='0 8 * * *',
    catchup=False,
) as dag:
    
    extract = PythonOperator(
        task_id='extract_job_postings',
        python_callable=extract_job_postings,
        sla=timedelta(minutes=2),  # 120 seconds max
        sla_miss_callback=sla_miss_callback,
    )
```

## Notes

- **SLA vs. timeout:** SLA is a *metric/alert*; timeout is *enforcement*. Use both: set `sla_seconds` for visibility and `execution_timeout` to hard-stop runaway tasks.
- **Callback overhead:** SLA miss callbacks should be lightweight (alerting, logging). Avoid heavy retries or complex logic—that belongs in task retry policies.
- **Upstream context matters:** A task's SLA should account for upstream variability. If your extract depends on external API latency, build a buffer rather than setting SLA to average runtime.
- **Alerting integration:** Wire SLA callbacks to Slack, PagerDuty, or logging systems so misses surface immediately, not in end-of-day reviews.
- **Revisit:** How SLAs interact with backfill runs (should backfills trigger SLA alerts?), and cost-benefit of aggressive SLAs (tighter SLAs = more alerts = alert fatigue).
