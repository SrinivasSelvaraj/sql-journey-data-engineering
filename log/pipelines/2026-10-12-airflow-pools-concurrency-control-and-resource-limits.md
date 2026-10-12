---
date: 2026-10-12
phase: pipelines
topic: Airflow pools: concurrency control and resource limits
---

# Airflow pools: concurrency control and resource limits

*Pipelines and orchestration*

## Concept

Airflow pools enforce concurrency limits by slotting tasks into named resource buckets. Each pool has a maximum number of concurrent slots; when all slots are occupied, queued tasks wait. This is essential when your tasks compete for shared resources—database connections, API rate limits, memory—that can't handle unlimited parallelism. Without pools, a DAG with 50 parallel tasks might exhaust your database connection pool, crash your API client, or overwhelm a downstream system, causing cascading failures.

Pools are configured at the instance level (with a default pool of 128 slots) and assigned to individual tasks via the `pool` parameter. A single task can consume multiple slots via `pool_slots`. This decouples task scheduling from execution capacity: Airflow's scheduler can still plan thousands of tasks, but the executor respects the pool ceiling when actually running them.

Think of pools as a traffic control mechanism. Without them, you're optimizing for "how fast can we run?"; with them, you're optimizing for "how fast can we run *without breaking downstream systems?*" They're particularly critical in production pipelines that interact with shared databases, APIs, or cloud services with throttling policies.

## Practice

**Problem:** Your `job_postings_fact` loads from three external job APIs (LinkedIn, Indeed, Glassdoor) in parallel. Each API allows only 5 concurrent requests and returns a 429 if exceeded. You have 15 tasks (5 per API) that fetch and insert batches into the fact table. How do you prevent rate-limit failures?

```sql
-- In your Airflow DAG code (Python):
-- 1. Create pools via Admin UI or code:
from airflow.models import Pool
Pool(pool_name='linkedin_api', slots=5, description='LinkedIn API concurrency')
Pool(pool_name='indeed_api', slots=5, description='Indeed API concurrency')
Pool(pool_name='glassdoor_api', slots=5, description='Glassdoor API concurrency')

-- 2. Assign tasks to pools:
fetch_linkedin_task = PythonOperator(
    task_id='fetch_linkedin_batch_1',
    python_callable=fetch_from_api,
    op_kwargs={'source': 'linkedin'},
    pool='linkedin_api',
    pool_slots=1,
    dag=dag
)

-- 3. Insert tasks use a shared 'database' pool to limit write parallelism:
insert_task = SQLExecuteQueryOperator(
    task_id='insert_job_postings_batch_1',
    sql='INSERT INTO job_postings_fact SELECT ...',
    pool='database_writes',
    pool_slots=1,
    dag=dag
)
```

Result: LinkedIn tasks queue to 5 max, Indeed to 5 max, Glassdoor to 5 max. No 429 errors. Inserts serialize if needed.

## Notes

- **Slot arithmetic matters:** If a task uses `pool_slots=2` in a 5-slot pool, only 2 more tasks can run. Undersizing slots starves your DAG; oversizing defeats the purpose.
- **Pool exhaustion is silent in the UI initially:** A queued task shows "scheduled" but never transitions to "running" if no slots free. Check the pool's current usage in Admin → Pools to diagnose hangs.
- **Pools + retries = exponential backoff:** When a task retries, it re-enters the queue. Combine pools with exponential_backoff_retry to avoid hammering rate-limited systems.
- **Connect to sensor patterns:** Pools are often paired with TaskSensor or ExternalTaskSensor to prevent resource waste on polling tasks; use `poke_interval` and `timeout` to avoid pool slot starvation by idle sensors.
- **Test pool capacity in staging:** Misconfigured pools cause silent delays in production. Run your DAG with reduced pool sizes to expose bottlenecks early.
