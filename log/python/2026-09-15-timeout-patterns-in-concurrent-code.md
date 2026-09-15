---
date: 2026-09-15
phase: python
topic: Timeout patterns in concurrent code
---

# Timeout patterns in concurrent code

*Python for data engineering*

## Concept

Timeout patterns protect concurrent code from hanging indefinitely when external services fail, network calls stall, or dependencies become unresponsive. In data pipelines, a missing timeout can cascade: one slow API endpoint blocks your entire job, queues back up, and workers appear frozen. Python's `asyncio.wait_for()`, `concurrent.futures.ThreadPoolExecutor(timeout=...)`, and libraries like `tenacity` let you set boundaries—fail fast or retry intelligently rather than waiting forever.

Timeouts are especially critical in ETL because external data sources (APIs, databases, message queues) don't always respond. A 30-second timeout on a single HTTP request that hangs becomes a 30-second delay per task; multiply that across thousands of records and your pipeline is dead in production. Without timeouts, you lose observability: you can't tell if the service is slow or broken, and you can't move on.

## Practice

**Problem:** You're loading job postings from an external API endpoint that occasionally hangs. You need to fetch 10,000 job records, parse them, and load them into a fact table. If any single API call takes more than 5 seconds, skip it and log the failure; if 3 consecutive calls fail, halt the entire load.

```python
import asyncio
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type
import logging

logger = logging.getLogger(__name__)

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=2, max=10),
    retry=retry_if_exception_type(TimeoutError),
    reraise=True
)
async def fetch_job_posting(session, job_id: int, timeout: int = 5) -> dict:
    """Fetch single job posting with timeout and retry logic."""
    try:
        async with asyncio.timeout(timeout):  # Python 3.11+
            async with session.get(f"https://api.example.com/jobs/{job_id}") as resp:
                resp.raise_for_status()
                return await resp.json()
    except asyncio.TimeoutError:
        logger.warning(f"Timeout fetching job_id={job_id}")
        raise TimeoutError(f"job_id {job_id} exceeded {timeout}s timeout")
    except Exception as e:
        logger.error(f"Error fetching job_id={job_id}: {e}")
        raise

async def load_job_postings(job_ids: list[int], batch_size: int = 100):
    """Load job postings with timeout per request and circuit breaker on consecutive failures."""
    results = []
    consecutive_failures = 0
    
    async with aiohttp.ClientSession() as session:
        for i in range(0, len(job_ids), batch_size):
            batch = job_ids[i:i + batch_size]
            tasks = [fetch_job_posting(session, jid) for jid in batch]
            
            responses = await asyncio.gather(*tasks, return_exceptions=True)
            
            for job_id, response in zip(batch, responses):
                if isinstance(response, Exception):
                    consecutive_failures += 1
                    logger.error(f"Failed job_id={job_id}: {response}")
                    if consecutive_failures >= 3:
                        raise RuntimeError(f"Circuit breaker tripped: {consecutive_failures} consecutive failures")
                else:
                    consecutive_failures = 0  # Reset on success
                    results.append({
                        "job_id": job_id,
                        "job_title_short": response.get("title"),
                        "salary_year_avg": response.get("salary"),
                        "job_work_from_home": response.get("remote", False),
                        "job_posted_date": response.get("posted_date"),
                        "job_location": response.get("location")
                    })
    
    return results
```

## Notes

- **Off-by-one timeout mistake:** Setting timeout on the whole batch instead of per-request; a batch of 100 calls with individual 1s timeouts needs 100s total, not 1s.
- **Timeout vs. retry confusion:** Timeout is a circuit breaker (stop waiting); retry is recovery logic (try again). Use both: retry on transient errors, timeout to prevent indefinite hangs.
- **Connection pooling and timeouts interact:** Thread/connection pool exhaustion can make timeouts trigger even when the service is fast; monitor pool size alongside timeout metrics.
- **Revisit:** Circuit breakers (Pybreaker), bulkheads (isolating slow tasks), and observability patterns (structured logging, traces) all depend on timeouts working correctly.
- **Testing timeout logic:** Use `pytest` fixtures with mocked slow endpoints (e.g., `asyncio.sleep()`) to verify timeouts fire and retries exhaust predictably.
