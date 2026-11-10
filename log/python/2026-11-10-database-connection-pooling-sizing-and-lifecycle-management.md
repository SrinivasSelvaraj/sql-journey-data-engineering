---
date: 2026-11-10
phase: python
topic: Database connection pooling: sizing and lifecycle management
---

# Database connection pooling: sizing and lifecycle management

*Python for data engineering*

## Concept

Connection pooling maintains a reusable set of database connections rather than opening and closing a new connection per query. Each connection is expensive: TCP handshake, authentication, transaction state initialization. Without pooling, a pipeline processing 10,000 rows with one query per row opens 10,000 connections. Most databases close idle connections after 5–30 minutes; pools keep them warm and ready. Pool sizing matters because too few connections bottleneck throughput (queries queue), while too many exhaust server memory and hit OS file descriptor limits. Lifecycle management means acquiring a connection from the pool when needed, returning it when done (even on error), and gracefully shutting down the pool at pipeline end—otherwise connections leak and the pipeline hangs or crashes.

In data pipelines, connection pooling is invisible until it fails. A loop that creates a new connection per batch write will fail with "too many connections" errors after 50–100 iterations on a typical database. Typed, testable pipelines require explicit pool initialization and cleanup—usually via context managers—so unit tests can inject mock pools and production code doesn't leak resources under load.

## Practice

**Problem:** Write a pipeline that loads 50,000 job postings in batches of 1,000, inserting each batch into `job_postings_fact`. Without pooling, the script fails mid-run with connection exhaustion.

```sql
-- Connection pool configuration (pseudocode pattern for psycopg2/SQLAlchemy):
-- min_size=5, max_size=20, timeout=30s, idle_timeout=600s

-- Batched insert using pooled connection:
INSERT INTO job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
VALUES 
  (%s, %s, %s, %s, %s, %s),
  (%s, %s, %s, %s, %s, %s),
  -- ... repeat 998 more times per batch
ON CONFLICT (job_id) DO UPDATE 
  SET salary_year_avg = EXCLUDED.salary_year_avg,
      job_posted_date = EXCLUDED.job_posted_date;
```

**Solution pattern (Python):**
```python
from sqlalchemy import create_engine
from contextlib import contextmanager

@contextmanager
def get_pool(db_url: str, min_size: int = 5, max_size: int = 20):
    engine = create_engine(
        db_url, 
        pool_size=max_size, 
        max_overflow=0,  # strict limit
        pool_pre_ping=True,  # test connection before use
        pool_recycle=3600  # recycle after 1hr
    )
    try:
        yield engine
    finally:
        engine.dispose()

def load_job_postings_batched(db_url: str, records: list[dict], batch_size: int = 1000):
    with get_pool(db_url) as pool:
        with pool.connect() as conn:
            for i in range(0, len(records), batch_size):
                batch = records[i : i + batch_size]
                conn.execute(
                    insert(job_postings_fact).values(batch)
                    .on_conflict_do_update(index_elements=['job_id'], ...)
                )
                conn.commit()
```

## Notes

- **Pool undersizing:** Setting `max_size=2` for concurrent workers causes queuing; set to ≥ (worker_count × queries_per_worker). Oversizing wastes memory—measure with `SELECT count(*) FROM pg_stat_activity`.
- **Leak patterns:** Forgetting `.dispose()` on shutdown, uncaught exceptions before connection return, or opening a connection outside the pool (e.g., `psycopg2.connect()` in a loop) nullifies pooling benefits.
- **Testing:** Mock pools with `unittest.mock.Mock()` or use SQLite in-memory for integration tests; never use production credentials in tests, and avoid sharing pools across test cases.
- **Adjacent topics:** Connection timeouts, query timeouts (separate from connection timeouts), and circuit breakers for cascading failure prevention; also relate to async connection pools (`asyncpg`, `motor`) for high-concurrency ETL.
- **Revisit:** Pool metrics (queue depth, idle count, active count) are critical to monitor in production; most ORMs expose them via `pool.status()` or logging.
