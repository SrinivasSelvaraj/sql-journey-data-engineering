---
date: 2026-09-15
phase: python
topic: Signal handling and graceful shutdown in daemons
---

# Signal handling and graceful shutdown in daemons

*Python for data engineering*

## Concept

Signal handling enables a running daemon to respond to OS signals (SIGTERM, SIGINT) and shut down gracefully instead of being forcibly killed mid-operation. Without it, your data pipeline may corrupt state, lose in-flight records, or leave locks held on databases and files. In data engineering, this is critical: a pipeline processing a 10 GB file that gets SIGKILL'd might leave the destination table half-written, downstream jobs blocked, or temporary files orphaned.

Python's `signal` module lets you register handlers that catch these signals before termination. A graceful shutdown typically means: finish the current batch, flush buffers, commit transactions, release locks, and clean up temp files—all before exiting. This is especially important in containerized environments (Kubernetes, Docker) where SIGTERM is the standard shutdown request, and in long-running ETL jobs where you need predictable state.

Without signal handling, your daemon ignores shutdown requests and forces orchestrators (or ops teams) to escalate to SIGKILL, causing cascading failures downstream. With it, your pipeline becomes a good citizen in production systems.

## Practice

**Problem:** Your job posting ETL pipeline runs continuously, reading from an API and inserting batches into `job_postings_fact`. A deployment triggers SIGTERM, but the process ignores it and keeps inserting. The transaction is never committed, and the next run tries to process the same records again, causing duplicates.

**Solution:**

```python
import signal
import logging
from contextlib import contextmanager
from typing import Generator

logger = logging.getLogger(__name__)
shutdown_event = False

def signal_handler(signum, frame):
    global shutdown_event
    logger.info(f"Received signal {signum}. Initiating graceful shutdown...")
    shutdown_event = True

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

@contextmanager
def batch_insert_transaction(conn, batch: list[dict]) -> Generator:
    """Context manager for transactional batch inserts with graceful exit."""
    cursor = conn.cursor()
    try:
        yield cursor
        cursor.executemany(
            """INSERT INTO job_postings_fact 
               (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
               VALUES (%s, %s, %s, %s, %s, %s)""",
            [(r['id'], r['title'], r['salary'], r['remote'], r['date'], r['location']) for r in batch]
        )
        conn.commit()
        logger.info(f"Committed batch of {len(batch)} records.")
    except Exception as e:
        conn.rollback()
        logger.error(f"Batch insert failed, rolled back: {e}")
        raise
    finally:
        cursor.close()

def fetch_and_load_jobs(conn, api_client, batch_size: int = 100):
    """Main ETL loop with signal-aware shutdown."""
    global shutdown_event
    batch = []
    
    for job_record in api_client.stream_jobs():
        if shutdown_event:
            logger.info("Shutdown signal received. Flushing final batch and exiting...")
            if batch:
                with batch_insert_transaction(conn, batch) as cursor:
                    pass
            break
        
        batch.append(job_record)
        
        if len(batch) >= batch_size:
            with batch_insert_transaction(conn, batch) as cursor:
                pass
            batch = []
    
    logger.info("ETL pipeline completed cleanly.")
```

## Notes

- **Signal safety:** Only use async-safe functions inside handlers (e.g., set a flag, not database calls). Use the flag to trigger cleanup in the main loop.
- **Timeout patterns:** Pair signal handling with timeout logic—if graceful shutdown takes >30s, log and exit anyway to prevent zombie processes.
- **Testing:** Mock `signal.signal()` and inject a `shutdown_event` flag so you can test graceful exit paths without actual OS signals.
- **Connection cleanup:** Always use context managers for database connections and cursors; ensure `conn.close()` runs in the main shutdown sequence, not just in handlers.
- **Related topics:** atexit module for cleanup-on-exit, multiprocessing signal propagation, orchestrator health checks (liveness/readiness probes), and structured logging with correlation IDs for tracing shutdown sequences.
