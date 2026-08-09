---
date: 2026-08-09
phase: python
topic: Exception design and retry with backoff
---

# Exception design and retry with backoff

*Python for data engineering*

## Concept

Exception design and retry with backoff are strategies for handling transient failures in data pipelines—network timeouts, rate limits, temporary service unavailability—without crashing or losing data. Rather than failing on the first error, you define *which* exceptions are recoverable, *how many* times to retry, and *how long* to wait between attempts using exponential backoff (wait 1s, then 2s, then 4s) to avoid overwhelming a recovering service. Without this, a single blip in an API or database connection kills your entire pipeline; with it, your code becomes resilient to real-world infrastructure noise. This matters most in ETL jobs that depend on external services (APIs, third-party databases, cloud storage) where you have no control over uptime but can control whether you retry intelligently.

## Practice

**Problem:** You're ingesting job postings from an external API into `job_postings_fact`. The API occasionally returns 429 (rate limit) or 503 (temporarily unavailable), but these errors are transient and resolve within seconds. Your current code fails immediately on any HTTP error, losing the batch.

**Solution:**

```python
import time
from typing import Any
from requests.exceptions import RequestException, Timeout, HTTPError
import requests

class TransientAPIError(Exception):
    """Raised for retryable API errors (rate limit, timeout, 5xx)."""
    pass

class PermanentAPIError(Exception):
    """Raised for non-retryable errors (auth, malformed request)."""
    pass

def fetch_job_postings(api_url: str, max_retries: int = 3, base_backoff: float = 1.0) -> list[dict[str, Any]]:
    """Fetch job postings with exponential backoff on transient errors."""
    for attempt in range(max_retries):
        try:
            response = requests.get(api_url, timeout=10)
            response.raise_for_status()
            return response.json()
        except (Timeout, ConnectionError) as e:
            raise TransientAPIError(f"Network timeout: {e}") from e
        except HTTPError as e:
            if e.response.status_code in (429, 503, 504):
                raise TransientAPIError(f"Service temporarily unavailable: {e.response.status_code}") from e
            elif e.response.status_code in (400, 401, 403, 404):
                raise PermanentAPIError(f"Request error (won't retry): {e.response.status_code}") from e
            raise TransientAPIError(f"HTTP error: {e.response.status_code}") from e
        except RequestException as e:
            raise PermanentAPIError(f"Unexpected request error: {e}") from e
        except Exception as e:
            raise PermanentAPIError(f"Unknown error: {e}") from e
        
        if attempt < max_retries - 1:
            wait_time = base_backoff * (2 ** attempt)
            print(f"Attempt {attempt + 1} failed. Retrying in {wait_time}s...")
            time.sleep(wait_time)
    
    raise TransientAPIError(f"Failed after {max_retries} retries")

# Usage in pipeline
try:
    postings = fetch_job_postings("https://api.example.com/jobs")
    # Insert into job_postings_fact
except PermanentAPIError as e:
    print(f"Pipeline halted (permanent error): {e}")
    raise
except TransientAPIError as e:
    print(f"Max retries exceeded (transient error): {e}")
    raise
```

## Notes

- **Distinguish exception types early**: Separate retryable (transient) from non-retryable (permanent) errors. Retrying a 401 auth failure wastes time; retrying a 503 is sensible. Use custom exception classes to enforce this distinction.
- **Exponential backoff prevents thundering herd**: Simple linear backoff (1s, 2s, 3s) or no backoff causes all clients to retry simultaneously when a service recovers, hammering it again. Exponential (1s, 2s, 4s, 8s) spreads load.
- **Set realistic timeouts and limits**: Infinite retries or unbounded wait times turn "resilience" into "hangs forever." Cap retries (3–5 is typical) and total wait time; fall back to alerting humans instead.
- **Connects to circuit breaker pattern**: After N consecutive failures, stop retrying entirely and fail fast. Prevents cascading failures in downstream systems.
- **Log and monitor every retry**: Without visibility, you won't know if your backoff strategy is working or if failures are actually permanent. Emit metrics (attempt count, wait duration, final status) to observability tools.
