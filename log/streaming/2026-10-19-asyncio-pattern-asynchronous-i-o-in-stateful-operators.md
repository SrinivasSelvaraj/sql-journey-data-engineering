---
date: 2026-10-19
phase: streaming
topic: Asyncio pattern: asynchronous I/O in stateful operators
---

# Asyncio pattern: asynchronous I/O in stateful operators

*Streaming and distributed processing*

## Concept

Asyncio enables a single Python thread to handle I/O-bound operations (network calls, database queries, file reads) concurrently without blocking. In stateful operators—processors that maintain internal state across streaming records—this matters because blocking operations stall the entire pipeline. When you're enriching job posting streams with external API calls (salary validation, location geocoding), a synchronous approach queues requests serially; asyncio lets you issue hundreds in flight while waiting, multiplying throughput.

Without asyncio in stateful operators, you hit a critical bottleneck: each record blocks downstream processing until its I/O completes. State accumulation (windowing, aggregation, deduplication) gets delayed, backpressure builds, and latency spikes unpredictably. The operator becomes a sequential step in what should be a parallel stage. This breaks SLAs on streaming jobs and wastes cluster resources holding idle threads.

The pattern works by replacing blocking calls with awaitable coroutines, allowing the event loop to switch between many pending operations. Stateful operators track which records are in-flight, use asyncio.gather() or TaskGroups to coordinate concurrent I/O, and emit results as they complete—not when all input has arrived.

## Practice

**Problem:** Enrich an incoming stream of job postings with external salary benchmarks (via HTTP API) and store validated records. The API has a 2-second latency per call and a rate limit of 10 requests/second. Processing 1000 postings/second with blocking calls would take hours; you need concurrent requests.

```sql
-- Pseudo-schema for state tracking in async operator
CREATE TEMP TABLE job_enrichment_state (
  job_id INT,
  job_title_short VARCHAR,
  salary_year_avg INT,
  job_posted_date DATE,
  job_location VARCHAR,
  benchmark_salary INT,
  api_request_ts TIMESTAMP,
  api_complete_ts TIMESTAMP,
  state VARCHAR -- 'pending', 'completed', 'failed'
);

-- Final insert once all async tasks resolve
INSERT INTO job_postings_enriched
SELECT 
  job_id,
  job_title_short,
  COALESCE(salary_year_avg, benchmark_salary) AS final_salary,
  job_posted_date,
  job_location
FROM job_enrichment_state
WHERE state = 'completed'
  AND api_complete_ts IS NOT NULL;
```

```python
import asyncio
import aiohttp
from collections import deque

class AsyncSalaryEnricher:
    def __init__(self, max_concurrent=10):
        self.pending = {}  # job_id -> coroutine
        self.max_concurrent = max_concurrent
        self.completed = deque()
    
    async def fetch_benchmark(self, session, job_id, title, location):
        try:
            async with session.get(
                f"https://api.salary.example.com/benchmark",
                params={"title": title, "location": location},
                timeout=aiohttp.ClientTimeout(total=5)
            ) as resp:
                data = await resp.json()
                return (job_id, data["benchmark_salary"], "completed")
        except Exception as e:
            return (job_id, None, "failed")
    
    async def process_batch(self, records):
        async with aiohttp.ClientSession() as session:
            tasks = [
                self.fetch_benchmark(session, r["job_id"], r["job_title_short"], r["job_location"])
                for r in records
            ]
            results = await asyncio.gather(*tasks, return_exceptions=True)
            return results

# Usage in streaming operator
async def enrich_job_stream(input_queue, output_queue, batch_size=100):
    enricher = AsyncSalaryEnricher(max_concurrent=10)
    batch = []
    
    while True:
        try:
            record = input_queue.get_nowait()
            batch.append(record)
        except:
            pass
        
        if len(batch) >= batch_size or (batch and time.time() % 2 < 0.01):
            results = await enricher.process_batch(batch)
            for (job_id, benchmark, state), orig_record in zip(results, batch):
                enriched = {**orig_record, "benchmark_salary": benchmark, "state": state}
                output_queue.put(enriched)
            batch = []
        
        await asyncio.sleep(0.01)
```

## Notes

- **Semaphore gotcha:** Without `asyncio.Semaphore(max_concurrent)`, all tasks launch immediately and can overwhelm the API or local file descriptors. Wrap gather() with semaphore acquisition to enforce backpressure.
- **State durability:** Async doesn't persist state. For exactly-once semantics, checkpoint pending task IDs to a state store (changelog topic, database) before acknowledging input; replay on recovery.
- **Error handling blindness:** `asyncio.gather(return
