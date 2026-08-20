---
date: 2026-08-20
phase: python
topic: Async IO with asyncio for concurrent API calls
---

# Async IO with asyncio for concurrent API calls

*Python for data engineering*

## Concept

Asyncio enables concurrent I/O-bound operations within a single thread by switching execution when one coroutine awaits (e.g., network latency). Without it, fetching 1000 job listings via sequential API calls takes 1000× the per-call latency; with asyncio, you fetch them concurrently and latency is dominated by the slowest call, not the sum. This matters in data pipelines fetching from paginated APIs, webhooks, or multiple external sources where network round-trip time dwarfs CPU work.

The key pattern: `async def`, `await`, and `asyncio.gather()` or `asyncio.TaskGroup`. Typed coroutines return `Coroutine[Any, Any, T]` where `T` is the actual result. Without proper error handling and timeouts, a single slow or hanging endpoint blocks the entire gather, and unbounded concurrency can exhaust file descriptors or trigger rate limits. Resilience requires per-task timeouts, exponential backoff, and bounded semaphores.

## Practice

**Problem:** Ingest job postings from a paginated API (100 pages, 10 posts per page) into the `job_postings_fact` table. Each page requires an HTTP GET; sequential fetching takes ~30 seconds (300ms per call × 100 pages). Implement concurrent fetching with error recovery and typed payloads.

```python
import asyncio
import aiohttp
from datetime import date
from typing import Optional
from dataclasses import dataclass

@dataclass
class JobPosting:
    job_id: int
    job_title_short: str
    salary_year_avg: Optional[int]
    job_work_from_home: bool
    job_posted_date: date
    job_location: str

async def fetch_page(
    session: aiohttp.ClientSession,
    page: int,
    semaphore: asyncio.Semaphore,
    max_retries: int = 3,
) -> list[JobPosting]:
    """Fetch single page with timeout, retries, and bounded concurrency."""
    async with semaphore:  # Limit concurrent connections
        for attempt in range(max_retries):
            try:
                async with session.get(
                    f"https://api.example.com/jobs?page={page}",
                    timeout=aiohttp.ClientTimeout(total=10),
                ) as resp:
                    resp.raise_for_status()
                    data = await resp.json()
                    return [
                        JobPosting(
                            job_id=item["id"],
                            job_title_short=item["title"][:50],
                            salary_year_avg=item.get("salary"),
                            job_work_from_home=item.get("remote", False),
                            job_posted_date=date.fromisoformat(item["posted"]),
                            job_location=item.get("location", "Unknown"),
                        )
                        for item in data.get("jobs", [])
                    ]
            except (aiohttp.ClientError, asyncio.TimeoutError) as e:
                if attempt == max_retries - 1:
                    raise
                await asyncio.sleep(2 ** attempt)  # Exponential backoff
                continue

async def ingest_all_pages(total_pages: int) -> list[JobPosting]:
    """Concurrently fetch all pages, return flattened results."""
    semaphore = asyncio.Semaphore(10)  # Max 10 concurrent requests
    async with aiohttp.ClientSession() as session:
        tasks = [
            fetch_page(session, page, semaphore)
            for page in range(1, total_pages + 1)
        ]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        postings = []
        for result in results:
            if isinstance(result, Exception):
                print(f"Page fetch failed: {result}")
            else:
                postings.extend(result)
        return postings

# Usage
if __name__ == "__main__":
    postings = asyncio.run(ingest_all_pages(total_pages=100))
    # Insert into job_postings_fact
```

## Notes

- **Semaphore bounds concurrency**: avoid spawning 10k tasks; 10–50 concurrent connections is typical. Without it, you hit OS limits (too many open files) or trigger API rate-limit bans.
- **Timeouts are mandatory**: use `aiohttp.ClientTimeout` or `asyncio.wait_for()`. Hanging requests silently stall `gather()`.
- **Return_exceptions=True prevents cascade failure**: one failed task doesn't cancel siblings; inspect results individually.
- **Asyncio is single-threaded**: CPU-bound work (parsing, hashing) blocks all coroutines. Use `ProcessPoolExecutor` for heavy computation.
- **Related**: structured concurrency (`TaskGroup` in Python 3.11+), connection pooling (`
