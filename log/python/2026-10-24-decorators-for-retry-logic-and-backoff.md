---
date: 2026-10-24
phase: python
topic: Decorators for retry logic and backoff
---

# Decorators for retry logic and backoff

*Python for data engineering*

## Concept

Decorators for retry logic and backoff automatically re-attempt failed operations with increasing delays, essential when your pipeline calls unstable APIs, databases, or cloud services. Without them, a single transient network blip or rate-limit response crashes your entire job; with them, you wrap a function once and get exponential backoff, jitter, and configurable failure thresholds for free.

The key insight: external systems fail *temporarily* far more often than they fail permanently. A 30-second pause followed by retry succeeds 80% of the time; immediate failure and crash succeeds 0% of the time. Data pipelines that depend on third-party APIs (job listings, enrichment services, authentication) live or die on retry strategy.

Without retry logic, you either give up immediately (data loss, incomplete runs) or implement ad-hoc retry loops inside every function (duplicated code, inconsistent behavior, hard to test). A decorator centralizes this concern: one `@retry_with_backoff` applied to your API call function handles all orchestration, logging, and state.

## Practice

**Problem:** Your pipeline fetches job postings from an external API to populate `job_postings_fact`. The API is rate-limited (429 responses) and occasionally times out (504). You need to retry with exponential backoff up to 5 times before logging the failure and moving on.

```python
import time
import functools
from typing import Callable, TypeVar, Any
from requests.exceptions import Timeout, HTTPError

F = TypeVar('F', bound=Callable[..., Any])

def retry_with_backoff(
    max_retries: int = 5,
    base_delay: float = 1.0,
    max_delay: float = 60.0,
    backoff_factor: float = 2.0,
    retriable_exceptions: tuple = (Timeout, ConnectionError)
) -> Callable[[F], F]:
    """Retry decorator with exponential backoff and jitter."""
    def decorator(func: F) -> F:
        @functools.wraps(func)
        def wrapper(*args, **kwargs) -> Any:
            attempt = 0
            delay = base_delay
            
            while attempt < max_retries:
                try:
                    return func(*args, **kwargs)
                except retriable_exceptions as e:
                    attempt += 1
                    if attempt >= max_retries:
                        raise
                    jittered_delay = delay * (0.5 + random.random())
                    print(f"Attempt {attempt} failed: {e}. Retrying in {jittered_delay:.1f}s")
                    time.sleep(jittered_delay)
                    delay = min(delay * backoff_factor, max_delay)
                except HTTPError as e:
                    if e.response.status_code == 429:
                        attempt += 1
                        if attempt >= max_retries:
                            raise
                        jittered_delay = delay * (0.5 + random.random())
                        print(f"Rate limited. Retry in {jittered_delay:.1f}s")
                        time.sleep(jittered_delay)
                        delay = min(delay * backoff_factor, max_delay)
                    else:
                        raise
        return wrapper
    return decorator

@retry_with_backoff(max_retries=5, base_delay=2.0)
def fetch_job_postings(api_url: str) -> list[dict]:
    """Fetch from API; transient failures are retried automatically."""
    response = requests.get(api_url, timeout=10)
    response.raise_for_status()
    return response.json()

# Usage in pipeline
postings = fetch_job_postings("https://api.example.com/jobs")
# Insert into job_postings_fact table
```

## Notes

- **Jitter matters:** Always add randomness (0.5–1.5× delay) to avoid thundering herd—if 100 clients retry at identical intervals, they'll all spike simultaneously and fail again.
- **Know what to retry:** Network timeouts and 429 (rate limit) are safe to retry; 401 (auth), 400 (bad request), 403 (forbidden) are permanent failures and waste time retrying.
- **Test the decorator separately:** Use `unittest.mock.patch` to simulate failures and verify retry counts and delays; don't test retry logic buried inside a live API call.
- **Connects to:** circuit breakers (stop retrying if failure rate is too high), async/await patterns (concurrent retries across multiple jobs), and observability (track retry counts per function per hour).
- **Revisit:** Libraries like `tenacity` and `backoff` provide battle-tested implementations; consider using them in production instead of rolling your own for edge cases (max jitter, deadline timeouts, custom backoff curves).
