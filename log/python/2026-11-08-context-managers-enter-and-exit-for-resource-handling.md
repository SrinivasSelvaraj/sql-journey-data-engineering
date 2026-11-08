---
date: 2026-11-08
phase: python
topic: Context managers: __enter__ and __exit__ for resource handling
---

# Context managers: __enter__ and __exit__ for resource handling

*Python for data engineering*

## Concept

Context managers (`__enter__` and `__exit__`) ensure resources are acquired and released safely, even when exceptions occur. In data engineering, this means database connections, file handles, and cloud credentials are never left open or leaked. Without them, you write try-finally blocks everywhere, code becomes verbose, and developers forget cleanup in edge cases—leading to connection pool exhaustion or hanging processes.

The `with` statement calls `__enter__` on acquisition and guarantees `__exit__` runs on exit (normal or via exception). This is critical in ETL pipelines where jobs process hundreds of files or batches: a single unclosed connection multiplied across 1000 tasks crashes your warehouse or exhausts your cloud quota within hours.

## Practice

**Problem:** You need to extract job postings from a database, transform them (filter remote-only roles, cap salary outliers), and load into a fact table. The connection must close even if transformation fails mid-pipeline.

```python
from contextlib import contextmanager
import sqlite3
import logging

@contextmanager
def db_connection(db_path: str):
    """Context manager for safe database connections."""
    conn = sqlite3.connect(db_path)
    try:
        yield conn
    except Exception as e:
        conn.rollback()
        logging.error(f"Transaction rolled back: {e}")
        raise
    finally:
        conn.close()

def load_job_postings(db_path: str, remote_only: bool = False):
    """Extract, transform, and load job postings safely."""
    with db_connection(db_path) as conn:
        cursor = conn.cursor()
        
        # Extract
        query = "SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location FROM job_postings"
        if remote_only:
            query += " WHERE job_work_from_home = 1"
        cursor.execute(query)
        rows = cursor.fetchall()
        
        # Transform
        cleaned_rows = [
            (row[0], row[1], min(row[2], 500000) if row[2] else None, row[3], row[4], row[5])
            for row in rows
        ]
        
        # Load
        cursor.executemany(
            "INSERT INTO job_postings_fact VALUES (?, ?, ?, ?, ?, ?)",
            cleaned_rows
        )
        conn.commit()
        logging.info(f"Loaded {cursor.rowcount} rows")
        # Connection automatically closes here, even if an exception occurred above
```

## Notes

- **Forgetting `finally`:** Without it, resources leak on exception. Always use `with` instead of manual `__enter__`/`__exit__` calls unless building a reusable manager.
- **Swallowing exceptions in `__exit__`:** If your `__exit__` catches and returns `True`, it suppresses the exception silently. Return `False` or don't catch unless you explicitly want to suppress.
- **Adjacent topics:** Decorators (`@contextmanager`), resource protocols (duck typing for `__enter__`/`__exit__`), testing with mocked contexts, and async context managers (`async with`).
- **Data engineering pitfall:** Many junior engineers leave Spark sessions, cloud storage connections, or SSH tunnels open in notebooks. Use context managers in all pipeline entrypoints, not just "important" scripts.
- **Worth revisiting:** Test that `__exit__` is called even on assertion errors or timeouts. Use `unittest.mock.patch` to verify cleanup in your test suite.
