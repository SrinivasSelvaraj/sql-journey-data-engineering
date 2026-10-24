---
date: 2026-10-24
phase: python
topic: Async/await for concurrent API calls
---

# Async/await for concurrent API calls

*Python for data engineering*

## Concept

Async/await lets you run multiple I/O-bound operations (API calls, database queries, file reads) concurrently without blocking. Instead of waiting for one HTTP request to finish before starting the next, async code yields control back to the event loop, which can dispatch other tasks. This matters in data pipelines because fetching job postings from multiple sources, enriching records via external APIs, or polling data endpoints becomes orders of magnitude faster—going from sequential (n × latency) to concurrent (max single latency).

Without async/await, a pipeline fetching 1000 job postings from 5 different APIs at 500ms per call takes 2500 seconds. With concurrent calls, it takes ~500 seconds. The cost is that you must use `async def`, `await`, and an event loop (usually `asyncio`), and any function you call must also be async-aware.

What breaks: synchronous libraries (like `requests`) will still block the event loop. You need async variants like `aiohttp`, `httpx`, or `asyncpg`. Forgetting to `await` a coroutine silently does nothing. Not managing connection pools causes resource exhaustion.

## Practice

**Problem:** You have a fact table `job_postings_fact` with 10,000 rows. You need to enrich each row by calling an external salary-prediction API (50ms per call). Sequentially, this takes 500 seconds. Write an async Python script that:
- Fetches all job postings from a database
- Makes concurrent API calls (max 20 in flight)
- Updates salary_year_avg with the prediction
- Handles timeouts and missing predictions gracefully

```python
import asyncio
import aiohttp
from typing import Optional
import asyncpg

async def fetch_salary_prediction(
    session: aiohttp.ClientSession,
    job_id: int,
    job_title: str,
) -> tuple[int, Optional[float]]:
    """Fetch prediction; return (job_id, predicted_salary or None)."""
    try:
        async with session.get(
            f"https://api.example.com/predict",
            params={"title": job_title},
            timeout=aiohttp.ClientTimeout(total=5),
        ) as resp:
            if resp.status == 200:
                data = await resp.json()
                return (job_id, data.get("predicted_salary"))
            return (job_id, None)
    except asyncio.TimeoutError:
        print(f"Timeout for job {job_id}")
        return (job_id, None)
    except Exception as e:
        print(f"Error fetching job {job_id}: {e}")
        return (job_id, None)

async def enrich_job_postings(db_dsn: str, api_base_url: str):
    """Main enrichment pipeline."""
    conn = await asyncpg.connect(db_dsn)
    rows = await conn.fetch("SELECT job_id, job_title_short FROM job_postings_fact")
    
    connector = aiohttp.TCPConnector(limit=20)
    async with aiohttp.ClientSession(connector=connector) as session:
        tasks = [
            fetch_salary_prediction(session, row["job_id"], row["job_title_short"])
            for row in rows
        ]
        results = await asyncio.gather(*tasks)
    
    # Batch update database
    async with conn.transaction():
        for job_id, predicted_salary in results:
            if predicted_salary:
                await conn.execute(
                    "UPDATE job_postings_fact SET salary_year_avg = $1 WHERE job_id = $2",
                    predicted_salary,
                    job_id,
                )
    
    await conn.close()

# Run it
asyncio.run(enrich_job_postings("postgresql://...", "https://api.example.com"))
```

## Notes

- **Gather vs. TaskGroup:** `asyncio.gather()` is simpler but doesn't cancel siblings on first exception. Use `asyncio.TaskGroup` (3.11+) for better error handling and automatic cleanup.
- **Connection pooling is mandatory:** With 20 concurrent requests, reuse a single `aiohttp.ClientSession` and configure `TCPConnector(limit=n)`. Creating new sessions per request defeats concurrency.
- **Async all the way down:** Any function called from async code must be awaitable. Mixing `requests.get()` in an async function will block the entire event loop.
- **Testing async code:** Use `pytest-asyncio` and mark tests with `@pytest.mark.asyncio`. Fixture setup (mocking APIs with `aioresponses`) is essential to avoid external dependencies.
- **Adjacent topics:** Semaphores for rate-limiting, `asyncpg` for async database pooling, structured concurrency patterns, and retry logic with `tenacity` or backoff decorators.
