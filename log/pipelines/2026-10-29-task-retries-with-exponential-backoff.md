---
date: 2026-10-29
phase: pipelines
topic: Task retries with exponential backoff
---

# Task retries with exponential backoff

*Pipelines and orchestration*

## Concept

Task retries with exponential backoff automatically re-execute failed tasks with increasing delays between attempts, rather than failing immediately. The delay grows exponentially (e.g., 2s, 4s, 8s, 16s) to avoid overwhelming a temporarily unavailable resource—a database, API, or network service recovering from degradation. Without it, transient failures (API rate limits, connection timeouts, temporary service outages) cascade into pipeline failures, requiring manual reruns and wasting data freshness. With it, most transient failures self-heal without human intervention.

This pattern is essential in production data pipelines because external dependencies are unreliable by design. A third-party job board API might throttle requests; a data warehouse might be under maintenance for 30 seconds; a network packet might be dropped. Exponential backoff respects service health (each retry waits longer, giving the resource time to recover) and avoids the "thundering herd" problem where all failed tasks retry simultaneously, reintroducing the same problem.

Retries without backoff—or with fixed delays—either hammer a struggling service (making recovery harder) or waste wall-clock time with unnecessary waits. Retries without limits cause infinite loops. The exponential backoff strategy balances resilience, efficiency, and operational courtesy.

## Practice

**Problem:** A data pipeline ingests job postings from an external API every hour. The API occasionally returns 503 errors during its maintenance window (typically 5–15 seconds). Currently, failed tasks block the entire pipeline. You need the pipeline to retry automatically, spacing out requests to let the API recover.

```sql
-- Airflow DAG with exponential backoff retry policy
from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime, timedelta

default_args = {
    'owner': 'data_eng',
    'retries': 3,
    'retry_delay': timedelta(seconds=2),
    'retry_exponential_backoff': True,
    'max_retry_delay': timedelta(seconds=600),  -- Cap at 10 minutes
}

def fetch_job_postings():
    """Calls external API; transient 503 errors will auto-retry."""
    import requests
    response = requests.get('https://api.jobs.example.com/postings')
    response.raise_for_status()
    return response.json()

def load_to_warehouse(ti):
    """Load fetched data into job_postings_fact."""
    postings = ti.xcom_pull(task_ids='fetch_jobs')
    # INSERT INTO job_postings_fact (job_id, job_title_short, salary_year_avg, 
    --   job_work_from_home, job_posted_date, job_location) VALUES (...)
    pass

dag = DAG(
    'job_postings_daily',
    default_args=default_args,
    start_date=datetime(2024, 1, 1),
    schedule_interval='@hourly',
)

fetch = PythonOperator(task_id='fetch_jobs', python_callable=fetch_job_postings, dag=dag)
load = PythonOperator(task_id='load_jobs', python_callable=load_to_warehouse, dag=dag)

fetch >> load
```

Retry attempt 1 waits 2s; attempt 2 waits 4s; attempt 3 waits 8s. If all retries fail, the task is marked failed and the DAG stops (loud failure). If any retry succeeds, execution continues.

## Notes

- **Idempotency is a prerequisite:** Retried tasks must produce the same result when run twice. Increment a counter rather than multiply existing values; use upserts (MERGE) instead of INSERT-only. Without idempotency, retries corrupt data.

- **Max retries and max delay prevent infinite loops:** Set `retries=3` or `retries=5` (not unlimited) and cap backoff duration to avoid waiting hours. A job board API likely recovers in seconds, not days.

- **Distinguish transient from permanent failures:** Retry on 503 (Service Unavailable), 429 (Rate Limited), timeout, connection reset. Don't retry on 401 (Unauthorized), 404 (Not Found), malformed JSON—those indicate code bugs, not temporary issues. Use custom exceptions to signal which errors are retryable.

- **Monitor retry rates:** If a task retries frequently, the underlying service is unstable or your pipeline load is too high. Set alerts on retry counts; they're an early warning before cascading failures.

- **Related patterns:** Circuit breakers (stop retrying after N consecutive failures to let service stabilize); dead-letter queues (move permanently failed tasks aside for manual review); jitter (add randomness to backoff times to desynchronize concurrent retries and prevent thundering herd).
