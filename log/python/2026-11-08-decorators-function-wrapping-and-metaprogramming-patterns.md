---
date: 2026-11-08
phase: python
topic: Decorators: function wrapping and metaprogramming patterns
---

# Decorators: function wrapping and metaprogramming patterns

*Python for data engineering*

## Concept

Decorators are functions that wrap other functions to modify their behavior without changing the original code—critical for data pipelines where you need consistent logging, retry logic, type validation, and error handling across dozens of ETL tasks. In Python, a decorator takes a function as input, returns a wrapper function that adds logic before/after execution, and is applied via the `@` symbol. In data engineering, decorators let you enforce schemas on pipeline outputs, automatically retry failed API calls, log execution time for performance debugging, and validate input data quality—all without duplicating that logic across every extraction function. Without decorators, you end up with scattered try-catch blocks, inconsistent logging, and brittle pipelines that fail silently or crash unpredictably when downstream schemas change or external APIs timeout.

## Practice

**Problem:** You have 15 data extraction functions pulling from different job boards. Each must validate that required fields exist, retry on timeout (max 3 times), log execution time, and tag results with source metadata. Writing this logic into each function creates maintenance burden and inconsistency.

**Solution:**

```python
import functools
import time
import logging
from typing import Callable, Any, TypeVar

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

F = TypeVar('F', bound=Callable[..., Any])

def retry_on_timeout(max_retries: int = 3) -> Callable[[F], F]:
    """Decorator: retry function up to max_retries on timeout."""
    def decorator(func: F) -> F:
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(1, max_retries + 1):
                try:
                    return func(*args, **kwargs)
                except TimeoutError as e:
                    if attempt == max_retries:
                        logger.error(f"{func.__name__} failed after {max_retries} retries: {e}")
                        raise
                    logger.warning(f"{func.__name__} timeout attempt {attempt}/{max_retries}, retrying...")
                    time.sleep(2 ** attempt)
        return wrapper
    return decorator

def log_execution_time(func: F) -> F:
    """Decorator: log function execution duration."""
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        start = time.time()
        result = func(*args, **kwargs)
        elapsed = time.time() - start
        logger.info(f"{func.__name__} executed in {elapsed:.2f}s")
        return result
    return wrapper

def validate_job_posting_schema(func: F) -> F:
    """Decorator: ensure output contains required job posting fields."""
    required_fields = {
        'job_id', 'job_title_short', 'salary_year_avg', 
        'job_work_from_home', 'job_posted_date', 'job_location'
    }
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        result = func(*args, **kwargs)
        if isinstance(result, list):
            for row in result:
                missing = required_fields - set(row.keys())
                if missing:
                    raise ValueError(f"Row missing fields: {missing}")
        return result
    return wrapper

# Usage: stack decorators from bottom (innermost) to top (outermost)
@log_execution_time
@retry_on_timeout(max_retries=3)
@validate_job_posting_schema
def extract_from_linkedin(page: int) -> list[dict]:
    """Fetch job postings from LinkedIn API."""
    # Simulated extraction
    return [
        {
            'job_id': 'LI_001',
            'job_title_short': 'Data Engineer',
            'salary_year_avg': 145000,
            'job_work_from_home': True,
            'job_posted_date': '2024-01-15',
            'job_location': 'Remote'
        }
    ]

# Call function; all decorators applied automatically
jobs = extract_from_linkedin(page=1)
```

## Notes

- **Execution order:** decorators wrap from bottom-up in the code, but execute outermost-inward; put `@log_execution_time` outermost so timing includes retry overhead.
- **functools.wraps() is essential:** without it, your wrapper loses the original function's `__name__`, `__doc__`, and metadata, breaking introspection tools and making debugging harder.
- **Closures capture context:** each decorator call creates a closure that captures parameters (like `max_retries`); this is why `retry_on_timeout(max_retries=3)` returns a decorator function rather than being the decorator itself.
- **Adjacent patterns:** decorators pair naturally with type hints, context managers (`with` statements for resource cleanup), and class-based decorators using `__call__` for stateful wrapping (e.g., caching results or
