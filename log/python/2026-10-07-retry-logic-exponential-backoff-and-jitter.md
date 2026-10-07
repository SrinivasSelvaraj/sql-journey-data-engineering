---
date: 2026-10-07
phase: python
topic: Retry logic: exponential backoff and jitter
---

# Retry logic: exponential backoff and jitter

*Python for data engineering*

## Concept

Retry logic with exponential backoff and jitter handles transient failures in data pipelines—network timeouts, rate limits, temporary service unavailability—by automatically retrying failed requests with increasing delays. Without it, a single hiccup causes pipeline failure. Exponential backoff (delay = base² attempt) prevents overwhelming a recovering service; jitter (randomized delay variance) prevents the "thundering herd" problem where many clients retry simultaneously at identical intervals, causing cascading failures.

This matters most when calling external APIs, databases under load, or cloud services with rate limits. A data pipeline fetching job postings via REST API will encounter occasional 429 (rate limit) or 503 (service unavailable) responses. Naive retry (immediate or fixed delay) either hammers the endpoint or wastes time; exponential backoff with jitter gracefully backs off while randomizing to spread load across time.

## Practice

**Problem:** Your pipeline fetches job postings from an external API endpoint that rate-limits at 100 requests/minute and occasionally returns 429 or 503. Build retry logic that respects these limits, survives transient failures, and fails fast on permanent errors.

```python
import random
import time
from typing import TypeVar, Callable, Any
from functools import wraps

T = TypeVar("T")

def retry_with_backoff(
    max_attempts: int = 5,
    base_delay: float = 1.0,
    max_delay: float = 60.0,
    jitter: bool = True,
) -> Callable[[Callable[..., T]], Callable[..., T]]:
    """Decorator: retry with exponential backoff and optional jitter."""
    def decorator(func: Callable[..., T]) -> Callable[..., T]:
        @wraps(func)
        def wrapper(*args: Any, **kwargs: Any) -> T:
            for attempt in range(1, max_attempts + 1):
                try:
                    return func(*args, **kwargs)
                except (ConnectionError, TimeoutError) as e:
                    if attempt == max_attempts:
                        raise
                    delay = min(base_delay * (2 ** (attempt - 1)), max_delay)
                    if jitter:
                        delay *= (0.5 + random.random())
                    print(f"Attempt {attempt} failed: {e}. Retrying in {delay:.2f}s...")
                    time.sleep(delay)
        return wrapper
    return decorator

@retry_with_backoff(max_attempts=5, base_delay=1.0, max_delay=60.0)
def fetch_job_postings(job_id: int) -> dict[str, Any]:
    """Fetch job posting from API; raises on transient/permanent failure."""
    # Simulates API call that may fail transiently
    import requests
    response = requests.get(
        f"https://api.example.com/jobs/{job_id}",
        timeout=5
    )
    response.raise_for_status()
    return response.json()

# Usage in pipeline
posting = fetch_job_postings(job_id=42)
```

## Notes

- **Don't retry permanent errors:** Only catch transient exceptions (timeout, connection reset, 429, 503). Never retry 400 (bad request) or 401 (auth failure)—these fail immediately and waste time.
- **Jitter is critical at scale:** Without randomization, thousands of clients retry in lockstep, re-creating the outage. Always add jitter when coordinating across distributed systems.
- **Connects to circuit breaker pattern:** After N consecutive failures, stop retrying and fast-fail instead. Exponential backoff + circuit breaker prevents cascade failures in microservice architectures.
- **Test with mock failures:** Use `unittest.mock.patch` to simulate transient errors (raise, then succeed) and verify retry counts and delay ranges.
- **Consider idempotency keys:** When retrying writes (INSERT, UPDATE), ensure the operation is idempotent or use idempotency tokens to prevent duplicate records in `job_postings_fact`.
