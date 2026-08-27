---
date: 2026-08-27
phase: python
topic: Context managers for resource cleanup and transaction handling
---

# Context managers for resource cleanup and transaction handling

*Python for data engineering*

## Concept

A context manager in Python is a protocol (using `__enter__` and `__exit__`) that guarantees resource cleanup, even when exceptions occur. In data engineering, this is critical for file handles, database connections, and transaction rollback—without it, leaked connections exhaust pools, uncommitted transactions lock tables, and half-written files corrupt pipelines.

The `with` statement invokes context managers. When you write `with open('data.csv') as f:`, Python calls `f.__enter__()` on entry and `f.__exit__()` on exit, regardless of whether the block succeeded or raised an exception. This matters because data pipelines are long-running; a single connection leak × 1000 jobs = deadlock.

Without context managers, you must manually call `.close()` or `.commit()/.rollback()`, which junior engineers skip or place incorrectly. Example: if a CSV parse fails mid-loop, an unclosed database cursor remains open. With context managers, cleanup is guaranteed.

## Practice

**Problem:** You're loading job_postings_fact from a CSV into PostgreSQL. The file is large; if the connection dies mid-insert, the transaction must roll back automatically. You need to handle file I/O and database writes atomically.

```python
import psycopg2
from contextlib import contextmanager

@contextmanager
def get_db_connection(dsn):
    """Context manager for database connections with auto-rollback on error."""
    conn = psycopg2.connect(dsn)
    try:
        yield conn
    except Exception:
        conn.rollback()
        raise
    else:
        conn.commit()
    finally:
        conn.close()

def load_job_postings(csv_path, dsn):
    """Load CSV into job_postings_fact with guaranteed cleanup."""
    with open(csv_path, 'r') as infile, get_db_connection(dsn) as conn:
        cur = conn.cursor()
        try:
            for line in infile:
                job_id, title, salary, wfh, posted_date, location = line.strip().split(',')
                cur.execute("""
                    INSERT INTO job_postings_fact 
                    (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
                    VALUES (%s, %s, %s, %s, %s, %s)
                """, (job_id, title, int(salary), wfh == 'true', posted_date, location))
        finally:
            cur.close()
```

Both file and connection close automatically; on exception, the transaction rolls back and the file is still closed.

## Notes

- **Mistake:** Using `with` for the file but manually `.commit()/.close()` on the connection. If the commit raises, you don't close. Always nest context managers.
- **Testing:** Mock context managers with `unittest.mock.patch` and `MagicMock().__enter__` to inject failures and verify rollback calls.
- **Adjacent:** Resource pooling (connection pools reuse `with` statements), decorators (`@contextmanager`), and `asyncio.StreamReader` context managers for async pipelines.
- **SQLAlchemy:** The ORM wraps this for you (`with Session() as session:`), but knowing the underlying protocol helps debug deadlocks.
- **Revisit:** Custom context managers for multi-step ETL stages (extract, transform, validate, load) where each stage needs independent rollback or cleanup.
