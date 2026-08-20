---
date: 2026-08-20
phase: python
topic: Decorator patterns: caching, timing and retry
---

# Decorator patterns: caching, timing and retry

*Python for data engineering*

## Concept

Decorators wrap functions to inject cross-cutting concerns—caching, timing, retry logic—without modifying the original function body. In data pipelines, this is critical because extraction, transformation, and load stages often hit external APIs, databases, or file systems that fail unpredictably or repeat expensive computation. A `@retry` decorator on an API call to fetch job postings handles transient network errors automatically; a `@cache` decorator on a slow aggregation query prevents redundant computation across pipeline runs; a `@timer` decorator surfaces performance bottlenecks without polluting business logic.

Without decorators, retry logic and caching scatter across your pipeline code as try-except blocks and manual dictionary lookups, making functions harder to test (you can't easily mock retry behavior) and harder to compose (if three functions all need caching, you write three versions of the same logic). Decorators keep concerns separated: your function stays pure, your infrastructure concerns stay in the decorator layer.

## Practice

**Problem:** Your job posting pipeline fetches data from an external API that fails 10–15% of the time with transient errors. You also repeatedly query a slow aggregation—average salary by job_title_short—that doesn't change within a single pipeline run. Write decorators to handle retries and cache the aggregation.

```python
import functools
import time
from typing import Any, Callable
import random

def retry(max_attempts: int = 3, delay: float = 1.0, backoff: float = 2.0) -> Callable:
    """Retry decorator with exponential backoff for transient failures."""
    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        def wrapper(*args, **kwargs) -> Any:
            attempt = 0
            current_delay = delay
            while attempt < max_attempts:
                try:
                    return func(*args, **kwargs)
                except (ConnectionError, TimeoutError) as e:
                    attempt += 1
                    if attempt >= max_attempts:
                        raise
                    print(f"Attempt {attempt} failed: {e}. Retrying in {current_delay}s...")
                    time.sleep(current_delay)
                    current_delay *= backoff
        return wrapper
    return decorator

def cache_result(func: Callable) -> Callable:
    """Simple in-memory cache for function results within a single pipeline run."""
    _cache = {}
    @functools.wraps(func)
    def wrapper(*args, **kwargs) -> Any:
        key = (func.__name__, args, tuple(sorted(kwargs.items())))
        if key not in _cache:
            _cache[key] = func(*args, **kwargs)
        return _cache[key]
    return wrapper

@retry(max_attempts=3, delay=0.5, backoff=2.0)
def fetch_job_postings(api_url: str) -> list[dict]:
    """Fetch job postings; retries on network failures."""
    if random.random() < 0.1:  # Simulate 10% failure rate
        raise ConnectionError("API temporarily unavailable")
    return [
        {"job_id": 1, "job_title_short": "Data Engineer", "salary_year_avg": 120000},
        {"job_id": 2, "job_title_short": "Analyst", "salary_year_avg": 95000},
    ]

@cache_result
def avg_salary_by_title(postings: tuple) -> dict[str, float]:
    """Expensive aggregation; cached within pipeline run."""
    time.sleep(2)  # Simulate slow query
    result = {}
    for post in postings:
        title = post["job_title_short"]
        result.setdefault(title, []).append(post["salary_year_avg"])
    return {title: sum(salaries) / len(salaries) for title, salaries in result.items()}

# Usage
postings = fetch_job_postings("https://api.example.com/jobs")
salary_stats = avg_salary_by_title(tuple(postings))  # Tuple for hashability
print(salary_stats)
salary_stats = avg_salary_by_title(tuple(postings))  # Second call hits cache
```

## Notes

- **Cache key brittleness:** Mutable arguments (lists, dicts) don't hash; convert to tuples or use `functools.lru_cache` with hashable types. Avoid caching across pipeline runs unless you explicitly manage cache invalidation.
- **Retry on what:** Retry transient errors (ConnectionError, TimeoutError) but not logic errors (ValueError, KeyError). A failed API call may succeed; a malformed response won't.
- **Decorator stacking order matters:** `@retry @cache` retries after checking cache (smart); `@cache @retry` caches failures (bad). Apply caching outermost.
- **Connects to:** function composition, dependency injection (pass cache/retry config), type hints (preserve function signature with `functools.wraps`), testing
