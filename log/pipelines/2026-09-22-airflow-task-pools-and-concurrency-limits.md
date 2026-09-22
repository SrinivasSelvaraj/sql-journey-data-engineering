---
date: 2026-09-22
phase: pipelines
topic: Airflow task pools and concurrency limits
---

# Airflow task pools and concurrency limits

*Pipelines and orchestration*

## Concept

Task pools in Airflow allow you to limit the concurrency of specific task groups across your entire DAG landscape, independent of global worker limits. Without them, resource-hungry tasks (database writes, API calls, external service connections) can overwhelm downstream systems or cause bottlenecks. A pool is essentially a named semaphore: you declare "only 3 tasks from this pool can run simultaneously" and assign tasks to it, creating a controlled queue.

Pools matter most when your DAG contains heterogeneous tasks with different resource costs. A single heavy transformation shouldn't starve lightweight metadata tasks, and you shouldn't need to resize your entire Airflow cluster to handle occasional spikes. They're also critical for respecting external rate limits—if your data warehouse allows 5 concurrent connections from your ETL user, a pool of size 5 ensures you never exceed it.

Without pools, you either over-provision your infrastructure (wasteful) or experience cascading failures when one slow task blocks critical downstream work. Pools make failure modes predictable: tasks queue gracefully instead of hanging or crashing.

## Practice

**Problem:** Your job_postings_fact table receives daily updates through three parallel ingestion tasks (API, CSV upload, database sync), each writing via `INSERT INTO`. Your data warehouse allows maximum 3 concurrent write connections. Without a pool limit, all tasks run freely and connection errors cascade. Design a pool strategy.

```sql
-- In Airflow UI or via code, create pool:
-- Pool name: "warehouse_writes"
-- Pool slots: 3

-- Then in your DAG definition:
ingest_api_task = PythonOperator(
    task_id='ingest_api_postings',
    pool='warehouse_writes',
    pool_slots=1,
    ...
)

ingest_csv_task = PythonOperator(
    task_id='ingest_csv_postings',
    pool='warehouse_writes',
    pool_slots=1,
    ...
)

ingest_db_sync_task = PythonOperator(
    task_id='ingest_db_sync_postings',
    pool='warehouse_writes',
    pool_slots=1,
    ...
)

-- All three tasks now queue fairly; at most 3 run concurrently.
-- If a fourth write task exists elsewhere in your DAGs, it also respects this pool.
```

## Notes

- **Mistake:** Confusing `pool_slots` (how many slots a single task consumes) with pool size (total available). A task with `pool_slots=2` occupies 2 of 3 slots; use slots to weight expensive operations.
- **Mistake:** Creating too many pools and losing visibility—start with one pool per resource constraint (warehouse writes, API calls, file I/O) rather than per-task pools.
- **Connection:** Pools complement `max_active_tasks_per_dag` (DAG-level concurrency) and `parallelism` (cluster-wide). Pools are finer-grained and cross-DAG.
- **Revisit:** Monitoring pool occupancy over time reveals capacity planning needs; Airflow UI shows pool metrics and queued tasks.
- **Related:** Use pools alongside task retry logic and alerting to build resilience; a queued task is safer than a failed one, but you need observability to catch stuck queues.
