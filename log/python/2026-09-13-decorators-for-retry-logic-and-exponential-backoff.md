---
date: 2026-09-13
phase: python
topic: Decorators for retry logic and exponential backoff
---

# Decorators for retry logic and exponential backoff

*Python for data engineering*

## Concept

Decorators for retry logic wrap functions to automatically re-execute them on failure, with exponential backoff spacing successive attempts further apart (1s, 2s, 4s, 8s…). This matters in data pipelines because external dependencies—APIs, databases, cloud storage—fail transiently: network timeouts, rate limits, temporary service outages. Without retry logic, a single flaky call kills your entire pipeline; with it, you tolerate brief failures and reduce alert fatigue.

Exponential backoff is critical because naive retry (immediate, constant delay) can hammer a struggling service and worsen the outage. By doubling the wait between attempts, you give the remote system time to recover while being persistent enough to succeed when service returns. The decorator pattern makes this reusable: apply `@retry(max_attempts=5, base_delay=1)` to any function—API calls, database connections, file reads—without rewriting control flow.

Without decorator-based retry, you either litter your code with try/except/sleep blocks (hard to test, inconsistent) or lose jobs to transient errors (expensive in production). Decorators centralize the strategy, make it testable in isolation, and keep pipeline logic clean.

## Practice

**Problem:** Your job postings pipeline fetches salary data from an external API that occasionally times out or rate-limits. You need to insert rows into `job_postings_fact` but the API call fails ~2% of the time. Manual retry on failure would be fragile; you need automatic retry with backoff that doesn't spam the API.

```python
import functools
import time
from typing import Callable, TypeVar, Any

T = TypeVar('T')

def retry(max_attempts: int = 3, base_delay: float = 1.0, backoff: float = 2.0):
    """Decorator: retry function on exception with exponential backoff."""
    def decorator(func: Callable[..., T]) -> Callable[..., T]:
        @functools.wraps(func)
        def wrapper(*args: Any, **kwargs: Any) -> T:
            attempt = 0
            while attempt < max_attempts:
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    attempt += 1
                    if attempt >= max_attempts:
                        raise
                    delay = base_delay * (backoff ** (attempt - 1))
                    print(f"Attempt {attempt} failed: {e}. Retrying in {delay}s...")
                    time.sleep(delay)
        return wrapper
    return decorator

# Usage in data pipeline
@retry(max_attempts=4, base_delay=1.0)
def fetch_salary_for_job(job_id: int) -> float:
    """Fetch from flaky API; retries automatically."""
    # Simulates external API call
    import random
    if random.random() < 0.2:  # 20% failure rate
        raise ConnectionError("API timeout")
    return 95000.0

# Insert into job_postings_fact with retry protection
def load_job_postings(job_ids: list[int]):
    for job_id in job_ids:
        salary = fetch_salary_for_job(job_id)  # Retries transparently
        # INSERT INTO job_postings_fact (job_id, salary_year_avg, ...) VALUES (...)
        print(f"Inserted job {job_id} with salary {salary}")

load_job_postings([101, 102, 103])
```

## Notes

- **Mistake: infinite retries.** Always set `max_attempts` and catch unrecoverable errors (auth failures, 404s) separately; don't retry those.
- **Jitter matters at scale.** Add random jitter to `delay` when many workers retry simultaneously to avoid thundering herd (all retry at same moment).
- **Connects to:** circuit breakers (stop retrying if service is down for hours), logging/monitoring (log each retry for debugging), and type hints (preserve return type with `TypeVar`).
- **Testing:** Mock the function to raise exceptions for first N calls, verify it succeeds on retry. Use `unittest.mock.patch` or `pytest.fixture` with side effects.
- **Revisit:** async/await + `asyncio.sleep()` for concurrent retries; structured logging to track retry chains across microservices.
