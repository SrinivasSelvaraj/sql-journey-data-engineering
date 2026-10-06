---
date: 2026-10-06
phase: python
topic: Decorator chaining and composition order
---

# Decorator chaining and composition order

*Python for data engineering*

## Concept

Decorator chaining applies multiple decorators to a single function; **order matters critically** because decorators wrap functions from bottom to top during definition, but execute outer-to-inner at runtime. In data pipelines, this means a `@validate_input` decorator placed above `@log_execution` will validate *before* logging occurs—affecting what gets logged and whether the function body runs at all. Without understanding composition order, you'll create silent failures (a validator runs after transformation, catching nothing), skip critical safety checks, or log incomplete/corrupted state. This is especially dangerous in ETL: if your retry decorator wraps your validation decorator, a bad record might retry indefinitely without ever being validated.

## Practice

**Problem:** Build a pipeline that extracts job postings, validates required fields exist and types are correct, logs execution time, and retries on transient database failures—but only if validation passed. Decorators must compose safely so validation happens first, then logging wraps the attempt, then retry wraps everything.

```sql
-- Fact table target
CREATE TABLE job_postings_fact (
    job_id INT PRIMARY KEY,
    job_title_short VARCHAR(50) NOT NULL,
    salary_year_avg DECIMAL(10,2),
    job_work_from_home BOOLEAN NOT NULL DEFAULT FALSE,
    job_posted_date DATE NOT NULL,
    job_location VARCHAR(100),
    loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Solution in Python (decorator order)
from functools import wraps
import logging
import time
from typing import Any
import sqlite3

logger = logging.getLogger(__name__)

def validate_input(func):
    """Innermost: runs first, closest to function logic."""
    @wraps(func)
    def wrapper(*args, **kwargs):
        row = args[0]
        required = ['job_id', 'job_title_short', 'job_posted_date', 'job_work_from_home']
        for field in required:
            if field not in row or row[field] is None:
                raise ValueError(f"Missing required field: {field}")
        if not isinstance(row['job_id'], int):
            raise TypeError(f"job_id must be int, got {type(row['job_id'])}")
        logger.info(f"Validation passed for job_id={row['job_id']}")
        return func(*args, **kwargs)
    return wrapper

def log_execution(func):
    """Middle: logs the attempt and result."""
    @wraps(func)
    def wrapper(*args, **kwargs):
        start = time.time()
        try:
            result = func(*args, **kwargs)
            elapsed = time.time() - start
            logger.info(f"{func.__name__} succeeded in {elapsed:.2f}s")
            return result
        except Exception as e:
            elapsed = time.time() - start
            logger.error(f"{func.__name__} failed after {elapsed:.2f}s: {e}")
            raise
    return wrapper

def retry_on_transient(max_retries=3, backoff=1.0):
    """Outermost: catches failures and retries."""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(1, max_retries + 1):
                try:
                    return func(*args, **kwargs)
                except ValueError:
                    # Validation error: never retry
                    raise
                except sqlite3.OperationalError as e:
                    if attempt == max_retries:
                        raise
                    logger.warning(f"Attempt {attempt} failed, retrying in {backoff}s: {e}")
                    time.sleep(backoff)
        return wrapper
    return decorator

# Apply decorators: validation first, logging second, retry last (outermost)
@retry_on_transient(max_retries=2)
@log_execution
@validate_input
def insert_job_posting(row: dict, conn) -> int:
    """Insert validated row into fact table."""
    cursor = conn.cursor()
    cursor.execute("""
        INSERT INTO job_postings_fact 
        (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
        VALUES (?, ?, ?, ?, ?, ?)
    """, (
        row['job_id'],
        row['job_title_short'],
        row.get('salary_year_avg'),
        row['job_work_from_home'],
        row['job_posted_date'],
        row.get('job_location')
    ))
    conn.commit()
    return row['job_id']
```

## Notes

- **Decorator order matters**: decorators are applied bottom-to-top at definition time, so `@validate` must be lowest to execute first. Reversing order means retry catches validation errors and loops forever.
- **Distinguish validation vs. runtime errors**: validation errors should *not
