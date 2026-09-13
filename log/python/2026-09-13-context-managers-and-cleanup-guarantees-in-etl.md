---
date: 2026-09-13
phase: python
topic: Context managers and cleanup guarantees in ETL
---

# Context managers and cleanup guarantees in ETL

*Python for data engineering*

## Concept

Context managers (`with` statements) guarantee cleanup code runs even when exceptions occur—critical in ETL where connections, file handles, and temporary resources must be released reliably. Without them, a failed transformation mid-pipeline leaves database connections open, temporary files undeleted, and locks held, cascading into downstream job failures and resource exhaustion.

In data pipelines, you typically need cleanup for: database connections (commit/rollback + close), file handles (especially when writing staging data), temporary directories, and acquired locks. The `__enter__` method sets up the resource, `__exit__` tears it down regardless of whether the `with` block succeeded, raised an exception, or was interrupted.

Without context managers, cleanup becomes scattered across try-finally blocks or—worse—optional and often skipped. A single forgotten `.close()` call in error handling means your production pipeline leaks connections nightly until the connection pool exhausts and all jobs hang.

## Practice

**Problem:** Load job postings from a CSV file into a staging table, transform salaries to USD, insert into the fact table, then clean up the staging table. If any step fails (bad CSV format, constraint violation), the staging table must be dropped and the connection closed cleanly.

```sql
-- Context manager pattern in Python (psycopg2 example)
import psycopg2
from contextlib import contextmanager

@contextmanager
def etl_pipeline(conn_string: str):
    """Ensures connection closes and staging table drops, even on error."""
    conn = None
    try:
        conn = psycopg2.connect(conn_string)
        yield conn
    finally:
        if conn:
            conn.rollback()  # Undo any uncommitted changes on error
            conn.close()

# Usage in ETL
def load_job_postings(csv_path: str, conn_string: str) -> int:
    with etl_pipeline(conn_string) as conn:
        cur = conn.cursor()
        cur.execute("CREATE TEMP TABLE job_postings_staging AS SELECT * FROM job_postings_fact LIMIT 0;")
        
        with open(csv_path, 'r') as f:
            cur.copy_from(f, 'job_postings_staging', sep=',')
        
        cur.execute("""
            INSERT INTO job_postings_fact 
            SELECT job_id, job_title_short, 
                   CAST(salary_year_avg AS NUMERIC), 
                   job_work_from_home, job_posted_date, job_location
            FROM job_postings_staging;
        """)
        conn.commit()
        return cur.rowcount
    # Connection and temp table are guaranteed cleaned up here
```

## Notes

- **Avoid bare `except:` in `__exit__`** — let exceptions propagate unless you explicitly handle and suppress them; swallowing errors hides pipeline failures.
- **Nested context managers** (`with A() as a, B() as b:`) are cleaner than try-finally chains; cleanup happens in reverse order automatically.
- **Temporary tables** in SQL also benefit from context manager wrapping—use `ON COMMIT DROP` for session-scoped cleanup or explicit DROP in `__exit__`.
- **Reconnect after exception** — sometimes a failed query leaves a connection in a bad state; consider `conn.rollback()` before `finally: conn.close()` to ensure a clean close.
- **Adjacent topics:** resource pooling (connection pools manage `__enter__/__exit__` for you), decorator `@contextmanager` for simpler custom cleanups, and `tempfile.TemporaryDirectory()` as a built-in context manager for staging directories.
