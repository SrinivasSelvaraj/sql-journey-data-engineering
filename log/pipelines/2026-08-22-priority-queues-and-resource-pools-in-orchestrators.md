---
date: 2026-08-22
phase: pipelines
topic: Priority queues and resource pools in orchestrators
---

# Priority queues and resource pools in orchestrators

*Pipelines and orchestration*

## Concept

Priority queues and resource pools are scheduling mechanisms that control *which* tasks run and *when*, preventing resource exhaustion and ensuring high-value work completes first. A priority queue ranks tasks by business importance (e.g., critical alerts before weekly reports); a resource pool limits concurrent execution (e.g., max 3 database connections, max 5 parallel Spark jobs). Without them, low-value tasks starve resources while critical pipelines queue indefinitely, and uncontrolled parallelism crashes shared infrastructure—databases lock, memory bloats, API rate limits trigger, and you lose visibility into what actually failed.

In orchestrators like Airflow, Prefect, or Dagster, priority queues integrate with executors (Celery, Kubernetes) to sort task execution order, while resource pools act as semaphores. A data warehouse ETL might assign priority 10 to fact table loads but priority 1 to exploratory analytics; when both queue simultaneously, the fact table runs first. Resource pools prevent 50 concurrent `dbt run` tasks from overwhelming your Snowflake warehouse.

The cost of omitting this: your orchestrator appears to work locally, but production silently deadlocks at scale. Tasks timeout waiting for resources that never become available. You can't distinguish a real failure from a resource contention failure, making runbook decisions impossible.

## Practice

**Problem:** You have three daily ETL jobs: `ingest_job_postings` (critical, must complete by 6 AM), `enrich_locations` (medium, depends on postings), and `generate_weekly_report` (low, for analytics). All three trigger at 5 AM. Your Airflow cluster has only 2 worker slots and limited database connections. Currently all three queue at once, the report hogs resources, and postings misses the SLA. How do you prioritize?

```sql
-- Set up a priority queue and resource pool in Airflow DAG:

from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime

default_args = {
    'owner': 'data_eng',
    'retries': 1,
}

with DAG(
    'etl_job_postings',
    default_args=default_args,
    start_date=datetime(2024, 1, 1),
    schedule_interval='0 5 * * *',
    catchup=False,
) as dag:
    
    # High-priority: fact table ingest
    ingest_postings = PythonOperator(
        task_id='ingest_job_postings',
        python_callable=ingest_postings_fn,
        pool='database_writes',      # Limit concurrent DB writes
        pool_slots=2,                 # Consume 2 slots (leaves 1 for others)
        priority_weight=100,          # Highest priority; runs first
    )
    
    # Medium-priority: enrichment depends on postings
    enrich = PythonOperator(
        task_id='enrich_locations',
        python_callable=enrich_fn,
        pool='database_writes',
        pool_slots=1,
        priority_weight=50,
        upstream_list=[ingest_postings],
    )
    
    # Low-priority: report can queue if resources unavailable
    report = PythonOperator(
        task_id='generate_weekly_report',
        python_callable=report_fn,
        pool='analytics_reads',       # Separate pool; doesn't block writes
        pool_slots=1,
        priority_weight=10,           # Lowest priority
    )
    
    # DAG dependencies
    ingest_postings >> enrich >> report
```

## Notes

- **Pool starvation trap:** Setting `pool_slots` too high (e.g., `pool_slots=10` when pool size is 10) means one task monopolizes the pool. Allocate based on actual resource cost, not arbitrarily.
- **Priority weight inverted in some systems:** Airflow uses higher numbers = higher priority; Prefect reverses this. Always verify your orchestrator's convention before tuning.
- **Resource pools ≠ dependency ordering:** A low-priority task with an upstream dependency will still wait for that dependency, even if high-priority tasks queue behind it. Combine pools with explicit DAG topology.
- **Monitoring blind spot:** Missing resource pool metrics in dashboards (queue depth, slot utilization, wait time) means you optimize blind. Log pool contention and alert when a pool hits 80% utilization consistently.
- **Adjacent: backpressure & graceful degradation:** When a pool exhausts, downstream tasks queue indefinitely. Consider fail-fast operators (timeouts, SLA thresholds) or circuit breakers to prevent cascading queueing.
