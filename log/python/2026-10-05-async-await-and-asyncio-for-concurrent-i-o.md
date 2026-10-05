---
date: 2026-10-05
phase: python
topic: Async/await and asyncio for concurrent I/O
---

# Async/await and asyncio for concurrent I/O

*Python for data engineering*

## Concept

Async/await and asyncio enable concurrent I/O operations within a single thread, crucial for data pipelines that fetch from multiple APIs, databases, or file systems simultaneously. Without concurrency, a pipeline fetching 100 job postings from a remote API with 500ms latency per request takes 50 seconds sequentially; with asyncio, the same requests can overlap, completing in ~1 second. This matters most when your bottleneck is waiting (network, disk, database queries) rather than CPU computation.

The pattern works by yielding control while waiting for I/O, allowing other coroutines to run. `async def` defines a coroutine, `await` pauses execution until a result arrives, and `asyncio.gather()` runs multiple coroutines concurrently. Without it, you either accept slow sequential processing, spawn heavy OS threads (expensive for hundreds of concurrent operations), or write callback spaghetti. For data engineers, this is the difference between a 10-minute data refresh and a 1-minute one.

Breaking without it: pipelines timeout fetching from slow APIs, parallelization requires multiprocessing (memory overhead, IPC complexity), or you resort to thread pools that don't scale to hundreds of concurrent connections. Type hints become harder to express with callbacks, and error handling in callback chains is error-prone.

## Practice

**Problem:** Fetch job posting metadata for 500 job IDs from an external API (each request takes ~200ms), validate the data, and insert into `job_postings_fact`. Sequential fetching takes 100 seconds; we need concurrent requests.

```python
import asyncio
import aiohttp
from datetime import date
from typing import TypedDict
import logging

class JobPostingData(TypedDict):
    job_id: int
    job_title_short: str
    salary_year_avg: float | None
    job_work_from_home: bool
    job_posted_date: date
    job_location: str

async def fetch_job_posting(
    session: aiohttp.ClientSession, job_id: int, base_url: str
) -> JobPostingData | None:
    """Fetch single job posting; return None on failure."""
    try:
        async with session.get(
            f"{base_url}/jobs/{job_id}", timeout=aiohttp.ClientTimeout(total=5)
        ) as resp:
            if resp.status == 200:
                data = await resp.json()
                return JobPostingData(
                    job_id=data["id"],
                    job_title_short=data["title"],
                    salary_year_avg=data.get("salary"),
                    job_work_from_home=data.get("remote", False),
                    job_posted_date=date.fromisoformat(data["posted_date"]),
                    job_location=data["location"],
                )
            logging.warning(f"API returned {resp.status} for job_id {job_id}")
            return None
    except asyncio.TimeoutError:
        logging.error(f"Timeout fetching job_id {job_id}")
        return None
    except (KeyError, ValueError) as e:
        logging.error(f"Parse error for job_id {job_id}: {e}")
        return None

async def fetch_all_postings(
    job_ids: list[int], base_url: str, max_concurrent: int = 10
) -> list[JobPostingData]:
    """Fetch multiple postings concurrently with semaphore to limit connections."""
    semaphore = asyncio.Semaphore(max_concurrent)
    
    async def bounded_fetch(session: aiohttp.ClientSession, job_id: int) -> JobPostingData | None:
        async with semaphore:
            return await fetch_job_posting(session, job_id, base_url)
    
    async with aiohttp.ClientSession() as session:
        tasks = [bounded_fetch(session, jid) for jid in job_ids]
        results = await asyncio.gather(*tasks, return_exceptions=False)
    
    return [r for r in results if r is not None]

# Usage in pipeline
postings = asyncio.run(
    fetch_all_postings(job_ids=[1, 2, 3, ...], base_url="https://api.example.com")
)
# Insert postings into job_postings_fact table
```

## Notes

- **Semaphore trap:** Without `asyncio.Semaphore`, launching all 500 requests at once can exhaust file descriptors or trigger API rate limits; cap concurrency to 10–50 depending on server constraints.
- **Exception handling:** `gather(..., return_exceptions=True)` returns exceptions as results instead of raising; filter and log failures separately so one bad job posting doesn't crash the entire fetch.
- **Adjacent topics:** Thread pools (`concurrent.futures`) for CPU-bound tasks in the same pipeline; `asyncio` for I/O only. Connection pooling (built into `aiohttp`); database drivers like `asyncpg`
