---
date: 2026-09-15
phase: python
topic: Thread safety: GIL limitations and race conditions
---

# Thread safety: GIL limitations and race conditions

*Python for data engineering*

## Concept

The Global Interpreter Lock (GIL) in CPython allows only one thread to execute Python bytecode at a time, making true parallelism impossible for CPU-bound work. In data pipelines, this means threading won't speed up JSON parsing, CSV transformation, or data validation—it will often slow it down due to context-switching overhead. The GIL *does* release during I/O operations (network calls, database queries, file reads), making threading useful for I/O-bound tasks like fetching from APIs or querying multiple databases concurrently.

Race conditions occur when multiple threads access shared state without synchronization. In data pipelines, this manifests when threads write to the same list, dictionary, or file simultaneously, corrupting data or losing records. For example, two threads appending to a Python list while one resizes it can lose entries entirely. Without locks, counters get incremented incorrectly, and batch inserts miss rows.

The practical rule: use `threading` for I/O-bound work (database connections, API calls) with proper locks around shared state; use `multiprocessing` or async frameworks for CPU-bound transformations; avoid threading for anything involving computation or unprotected writes.

## Practice

**Problem:** A data pipeline fetches job postings from multiple API endpoints concurrently, validates each row, and inserts into `job_postings_fact`. Two threads are writing to a shared validation error log and a batch insert list without synchronization. Records are lost and errors are overwritten.

```sql
-- Ensure job_postings_fact has robust constraints and timestamps
-- to detect missing or duplicate rows caused by race conditions

CREATE TABLE job_postings_fact (
  job_id BIGINT PRIMARY KEY,
  job_title_short VARCHAR(100) NOT NULL,
  salary_year_avg DECIMAL(10, 2),
  job_work_from_home BOOLEAN DEFAULT FALSE,
  job_posted_date DATE NOT NULL,
  job_location VARCHAR(255),
  inserted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  batch_id UUID NOT NULL,
  UNIQUE(job_id, batch_id)  -- Prevent duplicate inserts in concurrent scenario
);

-- Add audit table to catch race condition artifacts
CREATE TABLE job_postings_validation_errors (
  error_id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  job_id BIGINT,
  error_message TEXT NOT NULL,
  thread_id VARCHAR(50),
  logged_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  batch_id UUID NOT NULL
);
```

**Solution in Python:**
```python
import threading
from queue import Queue
from threading import Lock
from uuid import uuid4

batch_id = uuid4()
batch_lock = Lock()
valid_records = []
error_log = []

def fetch_and_validate(api_url, thread_id):
    records = fetch_from_api(api_url)
    for record in records:
        if is_valid(record):
            with batch_lock:  # Protect shared list
                valid_records.append(record)
        else:
            with batch_lock:  # Protect shared list
                error_log.append({
                    'job_id': record.get('job_id'),
                    'error': 'validation failed',
                    'thread_id': thread_id
                })

threads = [
    threading.Thread(target=fetch_and_validate, args=(url, i))
    for i, url in enumerate(api_urls)
]
for t in threads:
    t.start()
for t in threads:
    t.join()

# Insert with batch_id to detect loss
insert_batch(valid_records, batch_id, error_log)
```

## Notes

- **Lock contention kills concurrency:** Holding locks for long operations (e.g., slow database inserts) defeats threading's purpose. Use locks only for the critical section (list append), not the entire validation.
- **Queue over shared lists:** Use `queue.Queue` (thread-safe) instead of raw lists when possible; it handles locking internally and prevents most race conditions.
- **Test with `threading.Event` or semaphores:** Deliberately introduce timing delays in tests to expose race conditions; static code review won't catch them.
- **Connects to:** async/await (better for I/O-bound), multiprocessing (true CPU parallelism), connection pooling (thread-safe database access), and data integrity constraints (SQL-level safeguards).
- **Revisit:** GIL behavior changes in Python 3.13+; always profile your pipeline before and after adding threading to confirm it actually helps.
