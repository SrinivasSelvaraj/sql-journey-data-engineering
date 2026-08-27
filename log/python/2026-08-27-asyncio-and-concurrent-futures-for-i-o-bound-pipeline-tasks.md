---
date: 2026-08-27
phase: python
topic: Asyncio and concurrent.futures for I/O-bound pipeline tasks
---

# Asyncio and concurrent.futures for I/O-bound pipeline tasks

*Python for data engineering*

## Concept

In data pipelines, I/O-bound operations—API calls, database queries, file reads—spend most time waiting rather than computing. Python's `asyncio` (for coroutines) and `concurrent.futures` (for thread/process pools) let you overlap these waits, processing multiple jobs while one is blocked. Without concurrency, a pipeline fetching 1000 job postings via REST API sequentially might take 30+ minutes; with proper async patterns, the same work completes in 2–3 minutes.

`asyncio` suits network I/O and is lighter on resources; `concurrent.futures` (ThreadPoolExecutor) works better when you cannot rewrite legacy blocking code (like certain database drivers or synchronous libraries) and when you need process isolation. The trap: blocking operations on the event loop freeze *all* concurrent tasks. Type hints and structured exception handling become critical—silent failures in async tasks are easy to miss and cascade through pipeline stages.

Choose asyncio for new HTTP-heavy pipelines (with libraries like `aiohttp`); reach for ThreadPoolExecutor when wrapping blocking libraries or when threads suffice for I/O saturation. Both require careful resource limits to avoid overwhelming downstream services or exhausting system file descriptors.

## Practice

**Problem:** Fetch job posting details from an internal REST API for 500 job IDs, with a 100 ms latency per call. Insert or update records in the fact table atomically, respecting unique constraints on `job_id`. The API is rate-limited to 10 concurrent requests.

```sql
-- Fact table with unique constraint and indexed date range for incremental loads
CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR(100),
  salary_year_avg DECIMAL(10, 2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE NOT NULL,
  job_location VARCHAR(255),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(job_id),
  INDEX idx_posted_date (job_posted_date)
);

-- Python async pipeline (pseudocode structure)
import asyncio
import aiohttp
from typing import List, Dict
import logging

async def fetch_job_detail(session: aiohttp.ClientSession, job_id: int) -> Dict:
    """Fetch single job with retry logic."""
    try:
        async with session.get(f"/api/jobs/{job_id}", timeout=5) as resp:
            return await resp.json()
    except asyncio.TimeoutError:
        logging.error(f"Timeout fetching job {job_id}")
        return {}

async def fetch_all_jobs(job_ids: List[int], max_concurrent: int = 10) -> List[Dict]:
    """Fetch jobs with semaphore to respect rate limit."""
    semaphore = asyncio.Semaphore(max_concurrent)
    
    async def bounded_fetch(session, job_id):
        async with semaphore:
            return await fetch_job_detail(session, job_id)
    
    async with aiohttp.ClientSession() as session:
        tasks = [bounded_fetch(session, jid) for jid in job_ids]
        return await asyncio.gather(*tasks, return_exceptions=True)

-- Upsert with conflict handling (MySQL syntax)
INSERT INTO job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
VALUES (%s, %s, %s, %s, %s, %s)
ON DUPLICATE KEY UPDATE
  job_title_short = VALUES(job_title_short),
  salary_year_avg = VALUES(salary_year_avg),
  job_work_from_home = VALUES(job_work_from_home),
  job_posted_date = VALUES(job_posted_date),
  job_location = VALUES(job_location),
  updated_at = CURRENT_TIMESTAMP;
```

## Notes

- **Event loop blocking:** Never call `time.sleep()`, blocking DB drivers, or CPU-heavy work directly in async functions; use `loop.run_in_executor()` or move to a thread pool if unavoidable.
- **Exception handling:** `asyncio.gather(return_exceptions=True)` catches task failures without stopping siblings; always inspect results for exceptions before processing downstream.
- **Resource exhaustion:** Set connection pool limits (`connector=aiohttp.TCPConnector(limit=50)`) and semaphores to prevent file descriptor leaks or overwhelming APIs; monitor with `psutil` or container metrics.
- **Type safety:** Use `Coroutine[Any, Any, T]` return types and validate API response schemas with Pydantic early; silent None/KeyError in async pipelines are hard to debug.
- **Testing:** Mock async I/O with `unittest.mock.AsyncMock` and use `pytest-asyncio`; test both happy path and timeout/exception scenarios to catch cascading failures before production.
