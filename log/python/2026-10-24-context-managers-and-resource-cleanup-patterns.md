---
date: 2026-10-24
phase: python
topic: Context managers and resource cleanup patterns
---

# Context managers and resource cleanup patterns

*Python for data engineering*

## Concept

Context managers (the `with` statement) ensure resources like file handles, database connections, and network sockets are properly acquired and released, even when exceptions occur. In data pipelines, this is critical: an unclosed connection leaks memory and database resources; a half-written file leaves corrupted data in the warehouse. Python's context manager protocol (`__enter__` and `__exit__`) pairs setup with guaranteed cleanup, making code more robust than try-finally blocks and more readable.

When you load CSV files, query Postgres, or stream from APIs in a pipeline, forgetting `with` statements leaves dangling resources. The script may appear to work during development but fail under load or in production when connection pools exhaust. Type hints on context managers (e.g., `contextlib.contextmanager` return types) also make data flow explicit to linters and future maintainers.

## Practice

**Problem:** A data pipeline reads job postings from a CSV file, filters for remote roles, and inserts into a fact table. The code must handle missing salary data, partial file reads, and database disconnections without leaking file or connection handles.

```python
from contextlib import contextmanager
from typing import Generator
import csv
import psycopg2
from psycopg2.extras import execute_batch

@contextmanager
def get_db_connection(dsn: str) -> Generator:
    """Context manager for database connection with guaranteed cleanup."""
    conn = psycopg2.connect(dsn)
    try:
        yield conn
    finally:
        conn.close()

def load_job_postings(csv_path: str, dsn: str, batch_size: int = 100) -> int:
    """Load job postings; handles file and connection cleanup."""
    rows_inserted = 0
    
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        batch = []
        
        with get_db_connection(dsn) as conn:
            cur = conn.cursor()
            
            for row in reader:
                # Handle missing or invalid salary
                salary = row.get('salary_year_avg')
                salary_val = float(salary) if salary and salary.strip() else None
                
                batch.append((
                    int(row['job_id']),
                    row['job_title_short'],
                    salary_val,
                    row['job_work_from_home'].lower() == 'true',
                    row['job_posted_date'],
                    row['job_location']
                ))
                
                if len(batch) >= batch_size:
                    execute_batch(cur, 
                        "INSERT INTO job_postings_fact VALUES (%s, %s, %s, %s, %s, %s)",
                        batch)
                    rows_inserted += len(batch)
                    batch = []
            
            # Flush remaining rows
            if batch:
                execute_batch(cur,
                    "INSERT INTO job_postings_fact VALUES (%s, %s, %s, %s, %s, %s)",
                    batch)
                rows_inserted += len(batch)
            
            conn.commit()
    
    return rows_inserted
```

## Notes

- **Nested contexts matter:** Always nest file and database contexts in the correct order—open file first, then connection, so cleanup happens in reverse (connection closes before file). Forgetting this causes a closed connection to be referenced during final flush.
- **Don't silence exceptions in `__exit__`:** Returning `True` suppresses the exception; return `False` (default) to let it propagate for proper error logging and alerting in production.
- **Relates to:** exception handling strategies, logging patterns, and database connection pooling; also relevant for testing (mocking context managers with `unittest.mock.patch`).
- **Common mistake:** Using context managers inside loops without batching; this opens/closes connections per row, decimating performance. Batch operations first, then cleanup once.
- **Type hint tip:** Annotate context managers as `Generator[ResourceType, None, None]` to signal what they yield; helps static analysis catch misuse early.
