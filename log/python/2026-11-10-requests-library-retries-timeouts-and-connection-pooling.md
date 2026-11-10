---
date: 2026-11-10
phase: python
topic: Requests library: retries, timeouts and connection pooling
---

# Requests library: retries, timeouts and connection pooling

*Python for data engineering*

## Concept

The `requests` library provides three critical mechanisms for building robust data pipelines that call external APIs: **retries** automatically re-attempt failed requests, **timeouts** prevent your pipeline from hanging indefinitely, and **connection pooling** reuses TCP connections to reduce overhead. Without timeouts, a slow or unresponsive API can freeze your entire pipeline; without retries, transient failures (network blips, momentary 503s) will crash your job unnecessarily; without connection pooling, you'll open and close a new connection per request, wasting time and resources.

In data engineering, these three work together. A timeout tells the API "I'll wait max 5 seconds"; a retry policy says "if you're temporarily down, try again with backoff"; connection pooling ensures that if you're fetching thousands of job postings from an API, you're reusing the same TCP socket rather than negotiating 5000 handshakes. The `urllib3.Retry` class and `requests.adapters.HTTPAdapter` let you configure both, while the `Session` object automatically pools connections.

Without these safeguards, pipelines fail silently or hang: a 30-second timeout disappears into your logs, a single transient error fails your entire batch load, or you exhaust the API server's connection limits and get rate-limited harder than you should.

## Practice

**Problem:** You're building a job posting ingestion pipeline that calls an external API to fetch salary and location data. The API is occasionally slow (takes >10s) or returns 429/503 errors under load. Your current code hangs when the API is slow and fails on the first hiccup.

```python
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

def create_resilient_session(
    retries: int = 3,
    backoff_factor: float = 0.5,
    timeout_sec: int = 5,
    status_forcelist: list = None
) -> requests.Session:
    """
    Build a requests Session with retry logic and connection pooling.
    
    Args:
        retries: number of retry attempts
        backoff_factor: exponential backoff multiplier (0.5s, 1s, 2s, ...)
        timeout_sec: request timeout in seconds
        status_forcelist: HTTP codes to retry on (default: 429, 500, 502, 503, 504)
    """
    if status_forcelist is None:
        status_forcelist = [429, 500, 502, 503, 504]
    
    retry_strategy = Retry(
        total=retries,
        backoff_factor=backoff_factor,
        status_forcelist=status_forcelist,
        allowed_methods=["GET", "POST"]
    )
    
    adapter = HTTPAdapter(max_retries=retry_strategy, pool_connections=10, pool_maxsize=10)
    session = requests.Session()
    session.mount("https://", adapter)
    session.mount("http://", adapter)
    
    return session

# Usage in pipeline:
session = create_resilient_session(retries=3, timeout_sec=5)

try:
    response = session.get(
        "https://api.example.com/jobs",
        params={"job_id": 12345},
        timeout=5
    )
    response.raise_for_status()
    job_data = response.json()
except requests.exceptions.Timeout:
    print(f"Request timed out after 5 seconds")
except requests.exceptions.ConnectionError as e:
    print(f"Connection failed after retries: {e}")
except requests.exceptions.HTTPError as e:
    print(f"HTTP error: {e.response.status_code}")
```

## Notes

- **Timeout is mandatory at both layers**: set it in `session.get(..., timeout=5)` *and* in the `Retry` configuration; `requests` won't timeout by default and will hang forever waiting for a response.
- **Connection pooling size should match concurrency**: if you use 20 worker threads, set `pool_maxsize=20` to avoid blocking; too small and workers queue up, too large and you waste memory and might trigger API rate limits.
- **Distinguish retryable from fatal errors**: retry on 429 (rate limit), 503 (service unavailable), connection resets—but *not* on 400 (bad request), 401 (auth), 404 (not found); retrying those wastes time and API quota.
- **Backoff strategy matters for shared resources**: exponential backoff (`backoff_factor=0.5` gives 0.5s, 1s, 2s delays) prevents thundering herd when an API recovers; a fixed 1-second retry floods the server.
- **Session is stateful and thread-safe**: reuse one `Session` object across your pipeline; creating a new session per request defeats connection pooling and is expensive. Store it as a module-level or class-level variable if possible.
