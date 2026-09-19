---
date: 2026-09-19
phase: pipelines
topic: Retry strategies: exponential backoff vs jitter
---

# Retry strategies: exponential backoff vs jitter

*Pipelines and orchestration*

## Concept

Retry strategies determine how a failed pipeline task recovers—specifically, how many times it retries and with what delay between attempts. **Exponential backoff** increases the wait time after each failure (e.g., 1s → 2s → 4s → 8s), preventing a system already under stress from being hammered repeatedly. **Jitter** adds randomness to retry delays, preventing the "thundering herd" problem where many failed tasks retry simultaneously and cause cascading failures.

Without a retry strategy, transient failures (network blips, service hiccups, rate limits) kill your pipeline permanently. With naive retry (immediate retry), you risk overwhelming a struggling downstream service. With exponential backoff alone, synchronized retries from multiple pipelines can reignite the same failure in lockstep. Jitter breaks that synchronization: each retry delay varies, so recovery is staggered and the system breathes.

Use exponential backoff + jitter for external API calls, database operations, and cloud service dependencies. The formula is typically: `delay = min(max_delay, base_delay * (2 ^ attempt_number) + random(0, jitter_factor))`. In practice, 1–3 retries with 1–10 second base delays and ±25% jitter handle most transient faults without turning a hiccup into an hour of noise.

## Practice

**Problem:** Your daily `job_postings_fact` ETL extracts from a flaky third-party job board API. Network timeouts and 503 errors occur ~5% of the time. Your current pipeline retries immediately three times, which compounds the error and wastes time. You need to implement exponential backoff with jitter.

```sql
-- Pseudo-code for orchestrator (Airbnb's Airflow pattern)

from datetime import timedelta
from tenacity import retry, stop_after_attempt, wait_exponential

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(
        multiplier=1,      -- base_delay = 1 second
        min=1,             -- minimum 1 second
        max=10             -- cap at 10 seconds
    )
)
def extract_job_postings():
    """Fetch job postings from flaky API with exponential backoff + jitter."""
    response = requests.get(
        'https://api.jobboard.com/postings',
        timeout=5
    )
    response.raise_for_status()
    return response.json()

-- Then in your DAG:
task_extract = PythonOperator(
    task_id='extract_job_postings',
    python_callable=extract_job_postings,
    retries=3,
    retry_delay=timedelta(seconds=1),  -- initial backoff handled by @retry decorator
    execution_timeout=timedelta(minutes=5)
)
```

## Notes

- **Mistake:** Using `retry_delay` without exponential growth; retrying three times with 2-second intervals totals only 6 seconds, but if the service needs 30 seconds to recover, you fail anyway.
- **Mistake:** Adding jitter but forgetting a maximum cap; uncapped exponential backoff can delay retries by hours, making alerts seem like they vanished.
- **Adjacent:** Circuit breakers (fail fast if the service is clearly down) and bulkheads (isolate failures) work alongside retry strategies to protect the broader system.
- **Adjacent:** Observability matters here—log retry attempts with delay reasons so you can distinguish transient failures from systematic issues; dashboards should flag jobs that exhaust retries.
- **Revisit:** After implementing, measure failure rates and retry distributions; if you're hitting max retries frequently, increase `max_delay` or `max_attempts` or investigate root causes upstream.
