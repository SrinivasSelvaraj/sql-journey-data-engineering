---
date: 2026-09-15
phase: python
topic: Lock-free queues and thread-safe collections
---

# Lock-free queues and thread-safe collections

*Python for data engineering*

## Concept

Lock-free queues and thread-safe collections prevent data corruption when multiple threads or processes read/write simultaneously. In data pipelines, this matters when you have concurrent ingestion (multiple API pollers), parallel transformation workers, or background tasks logging metrics—all pushing to shared state without blocking. Python's `queue.Queue`, `threading.Lock`, and `multiprocessing.Manager` enforce mutual exclusion; without them, race conditions silently corrupt pipeline state, duplicate records, lose messages, or crash with `RuntimeError` mid-pipeline.

The GIL (Global Interpreter Lock) complicates this: threading in CPython doesn't give true parallelism for CPU-bound work, but I/O-bound tasks (API calls, database writes) still need synchronization. Lock-free designs using atomic operations or immutable data structures scale better, but Python's built-in collections (`dict`, `list`) are *not* thread-safe. A `dict` being updated by two threads can enter an inconsistent state, causing lookups to fail or iterate over phantom keys.

## Practice

**Problem:** You're building a data pipeline that reads job postings from an API endpoint using three concurrent worker threads. Each worker fetches a batch of postings and must write them to a thread-safe queue before a separate writer thread batches them into PostgreSQL. The queue must handle backpressure (block when full) and ensure no records are lost or duplicated.

```python
import queue
import threading
import time
from typing import NamedTuple
from datetime import datetime

class JobPosting(NamedTuple):
    job_id: int
    job_title_short: str
    salary_year_avg: float
    job_work_from_home: bool
    job_posted_date: str
    job_location: str

# Thread-safe queue with max size (backpressure)
posting_queue: queue.Queue[JobPosting] = queue.Queue(maxsize=1000)
lock_error_count = threading.Lock()
error_count = 0

def api_worker(worker_id: int, batch_size: int = 10):
    """Simulates fetching from API and enqueueing"""
    global error_count
    for i in range(batch_size):
        posting = JobPosting(
            job_id=worker_id * 1000 + i,
            job_title_short=f"Data Engineer {i}",
            salary_year_avg=120000.0,
            job_work_from_home=True,
            job_posted_date=datetime.now().isoformat(),
            job_location="Remote"
        )
        try:
            posting_queue.put(posting, timeout=5)
            print(f"[Worker {worker_id}] Enqueued job {posting.job_id}")
        except queue.Full:
            with lock_error_count:
                error_count += 1
            print(f"[Worker {worker_id}] Queue full, dropped job {posting.job_id}")

def db_writer():
    """Consumes queue and writes to database"""
    batch = []
    while True:
        try:
            posting = posting_queue.get(timeout=2)
            batch.append(posting)
            if len(batch) >= 5:
                print(f"[Writer] Batch insert: {len(batch)} rows")
                batch.clear()
        except queue.Empty:
            if batch:
                print(f"[Writer] Final batch insert: {len(batch)} rows")
                batch.clear()
            break

# Start workers
threads = []
for worker_id in range(3):
    t = threading.Thread(target=api_worker, args=(worker_id,))
    threads.append(t)
    t.start()

writer = threading.Thread(target=db_writer)
writer.start()

for t in threads:
    t.join()

posting_queue.join()  # Wait for queue to be processed
writer.join()

print(f"Pipeline complete. Errors: {error_count}")
```

## Notes

- **Queue over bare locks**: `queue.Queue` handles synchronization and FIFO semantics; raw `threading.Lock` + `list` is error-prone. Prefer the collection designed for your use case.
- **Deadlock risk**: If you acquire multiple locks, always in the same order. Nested locks without discipline cause threads to wait on each other circularly.
- **GIL and CPU-bound**: Threading won't parallelize CPU work in Python; use `multiprocessing.Pool` or `concurrent.futures.ProcessPoolExecutor` for CPU tasks. For I/O (network, disk), threading is fine.
- **Atomic operations matter**: Incrementing a counter (`x += 1`) is *not* atomic in Python; protect it with a lock or use `threading.Lock` + `queue` where mutation is encapsulated.
- **Testing concurrency is hard**: Use libraries like `pytest-timeout` and `threading.Event` to coordinate test threads; reproduce race conditions by inserting artificial delays in critical sections.
