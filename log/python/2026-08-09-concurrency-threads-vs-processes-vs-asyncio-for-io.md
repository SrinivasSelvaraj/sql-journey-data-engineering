---
date: 2026-08-09
phase: python
topic: Concurrency: threads vs processes vs asyncio for IO
---

# Concurrency: threads vs processes vs asyncio for IO

*Python for data engineering*

## Concept

Concurrency in Python data pipelines determines how efficiently you fetch data, transform batches, and write results without blocking. **Threads** share memory but hit the GIL (Global Interpreter Lock) on CPU tasks—useful only for IO waits. **Processes** bypass the GIL but are heavyweight, requiring serialization overhead; ideal for CPU-bound aggregations. **Asyncio** is lightweight and event-driven, perfect for thousands of concurrent IO operations (API calls, database reads) with minimal resource cost.

In data engineering, most pipelines are IO-bound: waiting on HTTP requests, database queries, or file systems. Blocking code wastes time—while one request completes, others sit idle. Without concurrency, a pipeline fetching 10,000 job postings at 100ms per request takes 1000 seconds; with asyncio, it takes ~10 seconds.

Choose based on your bottleneck: threads for simple blocking IO in small batches, asyncio for high-concurrency IO patterns, processes only when you're CPU-bound (rare in pure data pipelines). Mixing them carelessly introduces deadlocks, race conditions, and silent data loss.

## Practice

**Problem:** You fetch job postings from an API with a 100ms latency per request. You need 5,000 postings but the API rate limit allows 20 concurrent connections. A sequential loop takes 50,000ms. Rewrite it with asyncio.

```python
import asyncio
import aiohttp
from typing import List
from datetime import date

async def fetch_job_posting(
    session: aiohttp.ClientSession, 
    job_id: int
) -> dict:
    """Fetch single posting; raise on error."""
    url = f"https://api.example.com/jobs/{job_id}"
    async with session.get(url, timeout=aiohttp.ClientTimeout(total=5)) as resp:
        resp.raise_for_status()
        return await resp.json()

async def fetch_all_postings(job_ids: List[int], max_concurrent: int = 20) -> List[dict]:
    """Fetch all postings with concurrency limit."""
    connector = aiohttp.TCPConnector(limit=max_concurrent)
    async with aiohttp.ClientSession(connector=connector) as session:
        tasks = [fetch_job_posting(session, jid) for jid in job_ids]
        return await asyncio.gather(*tasks, return_exceptions=True)

async def load_to_fact_table(postings: List[dict]) -> None:
    """Transform and insert into job_postings_fact."""
    rows = [
        (
            p["id"],
            p["title"],
            p.get("salary_avg"),
            p.get("remote", False),
            p["posted_date"],
            p["location"]
        )
        for p in postings
        if isinstance(p, dict)  # Skip exceptions from gather()
    ]
    # Batch insert via psycopg or sqlalchemy
    async with create_async_engine() as engine:
        async with engine.begin() as conn:
            await conn.execute(
                insert(job_postings_fact).values(rows)
            )

# Run it
asyncio.run(fetch_all_postings(range(1, 5001)))
```

## Notes

- **GIL trap:** Threading won't parallelize CPU work (sorting, aggregation). Use `multiprocessing.Pool` or `concurrent.futures.ProcessPoolExecutor` for that, but accept serialization cost.
- **Asyncio requires all-in:** Libraries must be async-native (`aiohttp`, not `requests`; `asyncpg`, not `psycopg2`). Mixing blocking calls inside async functions blocks the entire event loop and defeats the purpose.
- **Error handling in gather():** Use `return_exceptions=True` to catch individual task failures without crashing the whole pipeline. Always validate responses before inserting.
- **Connection pooling:** Set `TCPConnector(limit=N)` to respect rate limits and avoid overwhelming the API or database. Too many concurrent connections = connection reset errors.
- **Revisit:** Event loop debugging (use `asyncio.create_task()` with names), streaming large result sets (don't load 5M rows at once), and hybrid patterns (asyncio for IO, threads for blocking legacy libraries).
