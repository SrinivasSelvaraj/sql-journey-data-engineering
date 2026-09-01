---
date: 2026-09-01
phase: pipelines
topic: Prefect: flow definition and task concurrency management
---

# Prefect: flow definition and task concurrency management

*Pipelines and orchestration*

## Concept

Prefect flows are task graphs that execute with explicit dependency management and configurable concurrency. A flow is a Python function decorated with `@flow` that orchestrates one or more `@task`-decorated functions; tasks are the atomic units that Prefect monitors, retries, and logs. Concurrency control—via task tags and work pool limits—prevents resource exhaustion when multiple tasks try to run simultaneously.

This matters because uncontrolled parallelism can overwhelm databases, APIs, or file systems. Without concurrency management, a flow pulling data from 10,000 job postings could spawn 10,000 simultaneous requests and crash the source. Prefect's concurrency limits act as a circuit breaker: tasks queue until a slot opens in their assigned work pool or tag-based limit, ensuring graceful degradation instead of cascading failures.

Flows fail loudly (exceptions propagate and are logged with full context) and rerun safely because Prefect tracks task state transitions and persists results. If a task fails, you can retry it, skip downstream dependents, or replay the entire flow from a checkpoint—all without re-executing tasks that already succeeded.

## Practice

**Problem:** You have a flow that enriches job posting records by fetching salary data from an external API for each job. The API allows max 5 concurrent requests. Without concurrency control, your flow would hammer the API and likely get rate-limited or blocked.

```sql
-- Conceptual schema (data layer)
CREATE TABLE job_postings_fact (
    job_id INT PRIMARY KEY,
    job_title_short VARCHAR(100),
    salary_year_avg DECIMAL(10, 2),
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    job_location VARCHAR(100)
);

-- Solution: Prefect flow with concurrency management
from prefect import flow, task
from prefect.concurrency.sync import rate_limit

@task(retries=2, retry_delay_seconds=5)
@rate_limit(max_calls=5, time_period=60)  # Max 5 calls per 60 seconds
def fetch_salary_data(job_id: int) -> dict:
    """Fetch salary from external API with rate limiting."""
    response = requests.get(f"https://api.example.com/salary/{job_id}")
    response.raise_for_status()
    return response.json()

@task
def insert_salary(job_id: int, salary_data: dict) -> None:
    """Insert enriched salary into database."""
    conn = psycopg2.connect(dbname="jobs")
    cursor = conn.cursor()
    cursor.execute(
        "UPDATE job_postings_fact SET salary_year_avg = %s WHERE job_id = %s",
        (salary_data['salary'], job_id)
    )
    conn.commit()
    cursor.close()
    conn.close()

@flow(name="enrich_job_salaries")
def enrich_job_salaries(job_ids: list[int]) -> None:
    """Orchestrate salary enrichment with concurrency control."""
    for job_id in job_ids:
        salary_data = fetch_salary_data(job_id)
        insert_salary(job_id, salary_data)
```

The `@rate_limit` decorator queues tasks so no more than 5 execute concurrently. Retries handle transient API failures. Each task's result is logged, enabling replay of failed jobs without re-fetching all 10,000.

## Notes

- **Common mistake:** Decorating a flow with `@task` or nesting flows inside flows without proper dependency declaration; use task returns and flow parameters to pass data explicitly.
- **Concurrency vs. parallelism:** Prefect concurrency limits control *how many tasks* execute simultaneously on a work pool, not thread/process count; pair with work pool configuration (threads, processes) for true parallelism.
- **Adjacent topic—subflows:** Large flows become hard to test and reuse; extract logical clusters into subflows (`@flow` calling `@flow`) to improve modularity and enable independent scheduling.
- **Checkpointing and caching:** Use `cache_key_fn` and `cache_expiration` on tasks to avoid re-running expensive operations (e.g., large file reads) within a single flow run or across runs.
- **Revisit:** State management (task state vs. flow state), artifact storage (logging structured outputs for post-run analysis), and work pool configuration for production deployments.
