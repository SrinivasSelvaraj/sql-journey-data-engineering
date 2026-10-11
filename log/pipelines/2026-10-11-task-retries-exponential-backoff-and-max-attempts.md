---
date: 2026-10-11
phase: pipelines
topic: Task retries: exponential backoff and max attempts
---

# Task retries: exponential backoff and max attempts

*Pipelines and orchestration*

## Concept

Task retries with exponential backoff are a resilience pattern where a failed task automatically re-executes with increasing delays between attempts, capped by a maximum retry count. Without them, transient failures—network timeouts, temporary database locks, API rate limits—immediately cascade into pipeline failures. With them, you trade a small amount of latency for dramatically higher reliability: a 99% success rate on individual tasks compounds across a 50-task pipeline to ~60% reliability without retries, but 99.5% with smart retries.

Exponential backoff matters because linear or immediate retries waste resources hammering a temporarily overloaded service. Instead, you wait 1 second, then 2 seconds, then 4, then 8—giving the upstream system time to recover. Max attempts prevents infinite loops: if a task fails 5 times with backoff, it's genuinely broken, not transient, and you should fail loudly rather than retry forever.

This breaks without implementation in orchestration tools (Airflow, dbt Cloud, Prefect) because dependent tasks hang indefinitely, alert fatigue sets in from flaky tests, and you lose the ability to distinguish transient infrastructure hiccups from real data quality issues.

## Practice

**Problem:** Your pipeline loads job postings from an external API hourly. The API occasionally returns 503 (service unavailable) for 30–60 seconds. Currently, a single 503 fails the entire pipeline and blocks downstream transformations.

```sql
-- Orchestration layer (Airflow DAG pseudocode / dbt YML)
-- Define retry logic on the extraction task

extract_job_postings_task:
  max_retries: 4
  retry_delay_seconds: 5
  exponential_backoff_base: 2
  # Retry sequence: 5s, 10s, 20s, 40s (total ~75s max wait)
  # If API recovers within this window, task succeeds

-- Then in your SQL transformation, assume data is present:
INSERT INTO job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT 
  id, 
  title, 
  salary, 
  remote_eligible, 
  posted_at, 
  location
FROM {{ ref('stg_job_postings_raw') }}
WHERE posted_at >= CURRENT_DATE - INTERVAL 1 DAY
  AND salary IS NOT NULL;
```

## Notes

- **Mistake: retrying non-idempotent tasks.** If a task inserts duplicate rows on retry without deduplication, exponential backoff masks bad design. Wrap writes in `INSERT ... WHERE NOT EXISTS` or use merge logic.
- **Jitter matters.** Add ±10% randomness to backoff delays to avoid thundering herd: if 100 tasks all retry at exactly t=4s, they all hammer the service again.
- **Connects to:** Dead letter queues (route persistent failures to investigation queues), circuit breakers (stop retrying if the service is consistently down), and observability (log retry counts to detect systematic degradation).
- **Mistake: confusing max_retries with timeout.** A task can retry 4 times but still exceed a 5-minute overall timeout if each attempt takes 90 seconds. Set both independently.
- **Revisit:** Retry budgets in multi-stage pipelines—if every task retries 4× and you have 50 tasks, total time can explode. Use task-level vs. DAG-level retry policies strategically.
