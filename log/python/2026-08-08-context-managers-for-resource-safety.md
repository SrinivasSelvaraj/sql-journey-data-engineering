---
date: 2026-08-08
phase: python
topic: Context managers for resource safety
---

# Context managers for resource safety

*Python for data engineering*

## Concept

Context managers (`with` statement) guarantee resource cleanup regardless of exceptions. In data pipelines, this means database connections, file handles, and temporary objects are released properly—preventing connection leaks, file descriptor exhaustion, and cascading failures. When extracting from APIs or reading multi-GB CSVs, a single uncaught exception can leave resources hanging; context managers ensure `__exit__` runs whether your pipeline succeeds or crashes mid-transform.

Without them, you rely on garbage collection timing (unreliable) or manual try-finally blocks (verbose, error-prone). A crashed job that doesn't close its Postgres connection leaves it open; 100 crashed runs exhaust the connection pool, and now your entire warehouse is unreachable. Context managers make resource safety automatic and enforceable.

## Practice

**Problem:** A data pipeline reads job postings from a CSV file, filters for remote positions with salary > $100k, and writes results to a database. If an error occurs during filtering or insertion, the file handle and database connection must close—otherwise subsequent runs fail with "too many open files" or connection pool exhaustion.

```python
import csv
import psycopg2
from contextlib import contextmanager

@contextmanager
def get_db_connection(dsn):
    conn = psycopg2.connect(dsn)
    try:
        yield conn
    finally:
        conn.close()

def load_job_postings(csv_path, dsn):
    with open(csv_path, 'r') as infile, \
         get_db_connection(dsn) as conn:
        reader = csv.DictReader(infile)
        cursor = conn.cursor()
        try:
            for row in reader:
                if row['job_work_from_home'] == 'True' and \
                   float(row['salary_year_avg']) > 100000:
                    cursor.execute(
                        "INSERT INTO job_postings_fact VALUES (%s, %s, %s, %s, %s, %s)",
                        (row['job_id'], row['job_title_short'], 
                         row['salary_year_avg'], row['job_work_from_home'],
                         row['job_posted_date'], row['job_location'])
                    )
            conn.commit()
        except Exception as e:
            conn.rollback()
            raise
        finally:
            cursor.close()
```

## Notes

- **Avoid bare `except`:** Always re-raise after cleanup (or use context managers—they handle it). Swallowing exceptions masks pipeline failures.
- **Test resource cleanup:** Use `unittest.mock` to verify `__exit__` is called. A test that passes but leaks connections is a false negative.
- **Combine with type hints:** Type the return value of custom context managers (`-> Generator[Connection, None, None]`) so callers know what they're working with.
- **Adjacent: dependency injection & factories.** Context managers pair well with connection pools (e.g., `psycopg2.pool.SimpleConnectionPool`) to avoid recreating expensive resources.
- **Revisit: transaction scope.** Context managers often wrap transactions too—know whether your `__exit__` commits or rolls back, and document it clearly.
