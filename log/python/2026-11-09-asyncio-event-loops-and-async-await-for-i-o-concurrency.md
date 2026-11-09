---
date: 2026-11-09
phase: python
topic: Asyncio: event loops and async/await for I/O concurrency
---

# Asyncio: event loops and async/await for I/O concurrency

*Python for data engineering*

## Concept

Asyncio provides single-threaded concurrency via an event loop that switches execution between coroutines during I/O waits, letting you fetch data from multiple APIs or databases without spawning threads. In data pipelines, this matters because external I/O (HTTP requests to data sources, database queries, file downloads) blocks execution; asyncio lets you issue 50 API calls and await their responses concurrently instead of serially. Without it, a pipeline fetching job postings from 10 sources would wait for each response sequentially—turning 10 seconds of total network time into 100+ seconds of wall-clock time.

The event loop is a dispatcher: it runs one coroutine until it hits an `await`, then switches to another waiting coroutine. Only CPU-bound work or blocking I/O (non-awaited sleep, synchronous database drivers) will freeze the loop and block all tasks. For data engineering, this means you can safely parallelize I/O-heavy ETL steps—scraping, API pagination, bulk inserts to staging tables—within a single process, avoiding multiprocessing overhead and shared-state headaches.

## Practice

**Problem:** Fetch job posting data from three paginated API endpoints concurrently, each returning `job_id`, `job_title_short`, `salary_year_avg`, `job_work_from_home`, `job_posted_date`, and `job_location`. Without asyncio, paginating through all three APIs takes 3× the time; with it, you fetch all pages in parallel and insert into a fact table.

```sql
CREATE TABLE IF NOT EXISTS job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR(100),
  salary_year_avg DECIMAL(10, 2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(100)
);

-- Insert fetched and validated async results
INSERT INTO job_postings_fact (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT 
  CAST(data->>'job_id' AS INT),
  data->>'job_title_short',
  CAST(NULLIF(data->>'salary_year_avg', '') AS DECIMAL),
  CAST(data->>'job_work_from_home' AS BOOLEAN),
  CAST(data->>'job_posted_date' AS DATE),
  data->>'job_location'
FROM (
  -- In practice, this staging table is populated by the async Python pipeline
  SELECT jsonb_object_agg(key, value) AS data 
  FROM staging_job_records
  WHERE validation_status = 'passed'
  GROUP BY batch_id
) validated
ON CONFLICT (job_id) DO UPDATE SET
  salary_year_avg = EXCLUDED.salary_year_avg,
  job_posted_date = EXCLUDED.job_posted_date;
```

## Notes

- **Don't mix sync and async carelessly:** calling a blocking function (e.g., `requests.get()`) inside an async function freezes the entire loop; use `aiohttp` for HTTP or wrap blocking calls with `loop.run_in_executor()`.
- **Error handling in concurrent tasks:** wrap each coroutine in try-except and collect failures separately; one failed API call shouldn't crash all tasks—gather results with `asyncio.gather(return_exceptions=True)`.
- **Debugging is harder:** stack traces are less linear; use logging at task boundaries and consider `asyncio.set_debug(True)` during development.
- **Connects to:** type hints (`Awaitable[List[dict]]`), validation pipelines (parse and validate each async result before insert), and backpressure (limit concurrent requests with `asyncio.Semaphore` to avoid overwhelming APIs).
- **Revisit:** the difference between `asyncio.gather()` (fire all, await all) and `asyncio.as_completed()` (process results as they arrive); the latter is better for heterogeneous latencies.
