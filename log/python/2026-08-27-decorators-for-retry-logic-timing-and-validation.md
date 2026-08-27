---
date: 2026-08-27
phase: python
topic: Decorators for retry logic, timing and validation
---

# Decorators for retry logic, timing and validation

*Python for data engineering*

## Concept

Decorators in Python wrap functions to add cross-cutting concerns—retry logic, timing, validation—without cluttering your core logic. In data pipelines, this matters because external APIs fail, transformations take unpredictable time, and malformed input arrives constantly. Without decorators, you scatter try-except blocks and timing code through every function, making code hard to test, maintain, and reason about.

A retry decorator lets you handle transient failures (network timeouts, rate limits) automatically. A timing decorator exposes performance bottlenecks in your ingestion or transformation steps. A validation decorator enforces contracts on inputs before they reach your pipeline logic—catching bad schemas or null values early, closer to the source. Together, they make pipelines resilient and observable.

## Practice

**Problem:** You ingest job postings from an external API that times out 10% of the time and returns malformed JSON occasionally. You need to retry failed requests, log how long each request takes, and validate that required fields (job_id, job_title_short, job_posted_date) are present before inserting into your `job_postings_fact` table.

```python
import time
import functools
import logging
from typing import Callable, Any, Dict, List
from datetime import datetime

logger = logging.getLogger(__name__)

def retry(max_attempts: int = 3, backoff_seconds: float = 1.0):
    """Retry decorator with exponential backoff."""
    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        def wrapper(*args, **kwargs) -> Any:
            for attempt in range(1, max_attempts + 1):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    if attempt == max_attempts:
                        logger.error(f"{func.__name__} failed after {max_attempts} attempts: {e}")
                        raise
                    wait_time = backoff_seconds * (2 ** (attempt - 1))
                    logger.warning(f"Attempt {attempt} failed, retrying in {wait_time}s: {e}")
                    time.sleep(wait_time)
        return wrapper
    return decorator

def timing(func: Callable) -> Callable:
    """Log execution time of a function."""
    @functools.wraps(func)
    def wrapper(*args, **kwargs) -> Any:
        start = time.perf_counter()
        result = func(*args, **kwargs)
        elapsed = time.perf_counter() - start
        logger.info(f"{func.__name__} took {elapsed:.3f}s")
        return result
    return wrapper

def validate_required_fields(required: List[str]):
    """Validate that a dict contains all required fields."""
    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        def wrapper(records: List[Dict[str, Any]], *args, **kwargs) -> Any:
            for record in records:
                missing = [field for field in required if field not in record or record[field] is None]
                if missing:
                    raise ValueError(f"Record missing required fields {missing}: {record}")
            return func(records, *args, **kwargs)
        return wrapper
    return decorator

@retry(max_attempts=3, backoff_seconds=2.0)
@timing
def fetch_job_postings(api_url: str) -> List[Dict[str, Any]]:
    """Fetch job postings from external API (times out, needs retry)."""
    # Simulates API call that may fail
    import requests
    response = requests.get(api_url, timeout=5)
    response.raise_for_status()
    return response.json()

@validate_required_fields(['job_id', 'job_title_short', 'job_posted_date'])
@timing
def load_to_fact_table(records: List[Dict[str, Any]], connection) -> None:
    """Insert validated records into job_postings_fact."""
    for record in records:
        connection.execute("""
            INSERT INTO job_postings_fact 
            (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (
            record['job_id'],
            record['job_title_short'],
            record.get('salary_year_avg'),
            record.get('job_work_from_home', False),
            record['job_posted_date'],
            record.get('job_location')
        ))
    connection.commit()

# Usage
postings = fetch_job_postings("https://api.example.com/jobs")  # Retries + timed
load_to_fact_table(postings, db_connection)  # Validated + timed
```

## Notes

- **Decorator order matters:** Apply `@retry` before `@timing` so retry attempts don
