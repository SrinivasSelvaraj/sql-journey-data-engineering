---
date: 2026-10-05
phase: python
topic: Context managers: __enter__ and __exit__ semantics
---

# Context managers: __enter__ and __exit__ semantics

*Python for data engineering*

## Concept

A context manager ensures setup and teardown logic runs reliably, even when exceptions occur. In Python, the `__enter__` method runs when entering a `with` block and should return a resource; `__exit__` runs when leaving (normally or via exception) and handles cleanup. This matters in data engineering because pipelines often open database connections, file handles, or temporary tables—if teardown fails silently, you leak resources, lock tables, or leave partial state behind. Without context managers, you either wrap everything in try-finally (verbose and error-prone) or skip cleanup entirely (dangerous in production).

The `__exit__` method receives three arguments: exception type, value, and traceback. If `__exit__` returns `True`, it suppresses the exception; returning `False` or `None` re-raises it. This dual role—cleanup *and* exception handling—makes context managers the standard pattern for safe, readable resource management in data pipelines.

## Practice

**Problem:** You load job postings into a staging table, transform them, then swap with the production table. If transformation fails midway, the staging table is left behind, cluttering the schema and confusing future runs. You need a context manager that creates the staging table on entry and drops it on exit, but only if the transformation fails—if it succeeds, rename it to production.

```python
class StagingTableContext:
    def __init__(self, conn, source_table, staging_name, prod_name):
        self.conn = conn
        self.source_table = source_table
        self.staging_name = staging_name
        self.prod_name = prod_name
    
    def __enter__(self):
        # Create staging table as copy of source
        self.conn.execute(f"""
            CREATE TABLE {self.staging_name} AS
            SELECT job_id, job_title_short, salary_year_avg, 
                   job_work_from_home, job_posted_date, job_location
            FROM {self.source_table}
        """)
        self.conn.commit()
        return self.staging_name
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type is not None:
            # Exception occurred: drop staging table
            self.conn.execute(f"DROP TABLE IF EXISTS {self.staging_name}")
            self.conn.commit()
            return False  # Re-raise the exception
        else:
            # Success: swap staging into production
            self.conn.execute(f"DROP TABLE IF EXISTS {self.prod_name}")
            self.conn.execute(f"ALTER TABLE {self.staging_name} RENAME TO {self.prod_name}")
            self.conn.commit()
            return False

# Usage
with StagingTableContext(conn, 'raw_postings', 'postings_staging', 'postings_fact') as staging:
    # Transform and insert into staging
    conn.execute(f"""
        UPDATE {staging}
        SET salary_year_avg = salary_year_avg * 1.05
        WHERE job_work_from_home = TRUE
    """)
    # If this fails, staging is cleaned up automatically
```

## Notes

- **Common mistake:** Catching exceptions in `__exit__` without re-raising them (returning `True` by accident). You hide the real error, making debugging a nightmare. Return `True` only if you genuinely want to suppress the exception.
- **File vs. database contexts differ:** `open()` closes file handles; database context managers must also handle transaction rollback. Always pair `COMMIT` in `__exit__` with `ROLLBACK` on exception paths.
- **Generators as context managers:** Use `@contextlib.contextmanager` decorator to write lightweight contexts without defining a class—useful for simple setup/teardown (e.g., timing a block, temporary config changes).
- **Nested contexts:** Multiple `with` statements or `with a() as x, b() as y:` stack cleanup in reverse order (LIFO). Critical when chaining connections or file handles.
- **Revisit alongside:** exception handling semantics (`raise ... from ...`), resource pooling (connection pools use context managers internally), and testing (mocking `__enter__` and `__exit__` for unit tests).
