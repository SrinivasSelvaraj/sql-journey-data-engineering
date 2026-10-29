---
date: 2026-10-29
phase: pipelines
topic: Pool and queue-based rate limiting
---

# Pool and queue-based rate limiting

*Pipelines and orchestration*

## Concept

Pool and queue-based rate limiting controls the concurrency and throughput of pipeline tasks to prevent overwhelming downstream systems—databases, APIs, cloud services—that have finite capacity. A **pool** (or semaphore) limits simultaneous task execution; a **queue** buffers requests and releases them at a sustainable rate. Without these controls, a pipeline bursts 1000 concurrent requests against an API with a 10-req/s limit, triggering throttling errors, connection resets, or service degradation that cascade into cascading retries and pipeline failures. This is especially critical in orchestrators like Airflow, dbt Cloud, or custom Python workflows where task parallelism is aggressive by default.

Rate limiting must be embedded at the point of resource consumption: when querying a heavily-used table, calling an external API, or writing to a shared sink. The pattern is straightforward—maintain a counter or queue, allow N tasks through at once, hold the rest, and release them as upstream tasks complete. Done right, the pipeline fails *loudly* (a queued task is not a failed task) and reruns safely (retried tasks rejoin the queue without special handling).

## Practice

**Problem:** A daily pipeline refreshes job_postings_fact by calling an external job board API for each job location. There are 50 distinct job_locations, but the API enforces a hard limit of 3 concurrent requests. Without rate limiting, all 50 location fetches start simultaneously, the API rejects 47 of them, and the pipeline retries chaotically.

```sql
-- Solution: Use a task pool in Airflow (or semaphore in other orchestrators)
-- In your DAG definition:

from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime

dag = DAG('job_postings_refresh', start_date=datetime(2024, 1, 1))

# Define the pool: max 3 concurrent tasks
# (Created via Airflow UI or CLI: airctl pool create api_pool 3)

def fetch_jobs_for_location(location):
    # Call external API for this location
    # Decorated tasks will respect the pool constraint
    pass

# Fetch tasks for each location, all assigned to the same pool
for location in ['New York', 'San Francisco', 'Austin', ...]:
    fetch_task = PythonOperator(
        task_id=f'fetch_{location.replace(" ", "_")}',
        python_callable=fetch_jobs_for_location,
        op_kwargs={'location': location},
        pool='api_pool',  # Max 3 tasks run simultaneously
        pool_slots=1      # Each task occupies 1 slot
    )
```

The orchestrator queues all 50 tasks but executes only 3 at a time. Failed tasks retry within the queue; no special handling needed.

## Notes

- **Pool vs. queue semantics:** Pools are stateful concurrency limits (slots); queues are FIFO buffers. Airflow uses pools; message brokers (Kafka, SQS) combine both. Know your tool's terminology.
- **Slot accounting matters:** If a task holds a pool slot for 10 minutes while waiting for I/O, other tasks starve. Use connection pools (SQLAlchemy, psycopg2) *inside* tasks to decouple concurrency from I/O blocking.
- **Common mistake:** Setting pool size equal to peak parallelism without measuring downstream capacity. Profile your target system first—a database may handle 3 concurrent queries but queue 50 if you're not careful.
- **Adjacent: backpressure and circuit breakers.** Rate limiting is passive (slow down). A circuit breaker actively *stops* requests when a threshold is breached. Together they form a resilient boundary.
- **Revisit: task dependencies vs. pools.** Pools limit concurrent *execution*; dependencies determine *order*. Use both: serialize critical writes with dependencies, parallelize independent API calls with pools.
