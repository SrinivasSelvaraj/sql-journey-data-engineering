---
date: 2026-09-13
phase: python
topic: Asyncio patterns for non-blocking I/O in pipelines
---

# Asyncio patterns for non-blocking I/O in pipelines

*Python for data engineering*

## Concept

Asyncio enables non-blocking I/O by allowing a single thread to pause coroutines while waiting for network or disk operations, then resume them when data arrives. In data pipelines, this matters because Extract and Load phases often involve hundreds of API calls or database inserts—blocking on each one sequentially wastes wall-clock time. Without asyncio patterns, a pipeline fetching 1000 job postings over HTTP might take 20 minutes serial; with concurrent coroutines it can finish in 2 minutes using the same hardware.

The pattern breaks down when you mix blocking libraries (like `requests` or standard file I/O) with async code, or when you don't properly handle exceptions across multiple concurrent tasks. A single unhandled exception in one coroutine can silently fail while others continue, corrupting your data load. Type hints become critical here—`async def fetch() -> Awaitable[list[JobPosting]]` makes intent explicit and catches callback-hell mistakes at lint time.

Asyncio also requires careful resource management: connection pools, semaphores to limit concurrency, and proper cleanup via context managers. A naive pattern that spawns 10,000 concurrent tasks will exhaust file descriptors. The goal is sustainable throughput—balancing I/O parallelism against memory and system limits.

## Practice

**Problem:** You have 500 job posting URLs to fetch from an API that rate-limits to 10 req/sec. Build a pipeline that respects the limit, retries on transient failures, and loads valid records into `job_postings_fact` while skipping malformed responses—all without blocking.

```python
import asyncio
import aiohttp
from typing import TypedDict
from datetime import datetime

class JobPosting(TypedDict):
    job_id: int
    job_title_short: str
    salary_year_avg: int | None
    job_work_from_home: bool
    job_posted_date: str
    job_location: str

async def fetch_with_retry(
    session: aiohttp.ClientSession,
    url: str,
    semaphore: asyncio.Semaphore,
    max_retries: int = 3
) -> JobPosting | None:
    """Fetch a single job posting with rate limit and retry logic."""
    for attempt in range(max_retries):
        try:
            async with semaphore:  # Enforce concurrency limit (10 req/sec)
                async with session.get(url, timeout=10) as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        # Validate required fields
                        return JobPosting(
                            job_id=int(data["id"]),
                            job_title_short=str(data["title"])[:50],
                            salary_year_avg=data.get("salary"),
                            job_work_from_home=bool(data.get("remote", False)),
                            job_posted_date=data["posted_date"],
                            job_location=data.get("location", "unknown")
                        )
                    elif resp.status == 429:  # Rate limit
                        await asyncio.sleep(2 ** attempt)  # Exponential backoff
                    else:
                        return None
        except (asyncio.TimeoutError, aiohttp.ClientError):
            if attempt < max_retries - 1:
                await asyncio.sleep(1)
            else:
                return None
    return None

async def load_pipeline(urls: list[str], db_conn) -> int:
    """Orchestrate concurrent fetches and batch insert."""
    semaphore = asyncio.Semaphore(10)  # 10 concurrent requests
    loaded_count = 0
    
    async with aiohttp.ClientSession() as session:
        tasks = [fetch_with_retry(session, url, semaphore) for url in urls]
        results = await asyncio.gather(*tasks, return_exceptions=True)
    
    # Filter valid records, skip exceptions and None
    valid_postings = [
        r for r in results 
        if isinstance(r, dict) and r is not None
    ]
    
    # Batch insert to job_postings_fact
    if valid_postings:
        placeholders = ",".join(["%s"] * len(valid_postings[0]))
        query = f"INSERT INTO job_postings_fact VALUES ({placeholders})"
        for posting in valid_postings:
            await db_conn.execute(query, tuple(posting.values()))
        loaded_count = len(valid_postings)
    
    return loaded_count

# Usage
# asyncio.run(load_pipeline(job_urls, db_connection))
```

## Notes

- **Exception handling trap:** `asyncio.gather(*tasks)` by default stops on first exception; use `return_exceptions=True` to collect all results, then filter. Unhandled exceptions in background tasks silently perish—always wrap in try/except or use `add_done_callback()`.
- **Semaph
