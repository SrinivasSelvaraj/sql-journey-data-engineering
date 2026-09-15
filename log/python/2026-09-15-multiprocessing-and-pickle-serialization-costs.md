---
date: 2026-09-15
phase: python
topic: Multiprocessing and pickle serialization costs
---

# Multiprocessing and pickle serialization costs

*Python for data engineering*

## Concept

Multiprocessing in Python spawns separate processes to bypass the Global Interpreter Lock (GIL), enabling true parallelism for CPU-bound tasks. However, each process requires serialization (pickling) of data to pass between processes—objects are converted to bytes, sent over pipes, and reconstructed. This serialization overhead is substantial: large DataFrames, complex objects, or frequent message passing can make multiprocessing slower than single-threaded code.

In data pipelines, this matters when processing millions of rows across transformations. A common pattern is splitting input data, distributing chunks to worker processes, and gathering results. If each chunk is a 100MB DataFrame and you have 8 workers exchanging pickled data constantly, serialization can consume 30–50% of execution time, nullifying parallelism gains.

Multiprocessing breaks down when: objects contain unpickleable state (file handles, database connections, locks), when data is exchanged too frequently (thousands of small messages per second), or when the serialization cost exceeds the computation savings. Testing becomes harder because multiprocessing obscures stack traces and state isolation complicates mocking.

## Practice

**Problem:** You have a 10M-row job postings table. You want to enrich `job_title_short` with a category lookup (100K rows) in parallel across 4 processes. A naive approach pickles the entire lookup table and sends it to each worker, then pickles enriched chunks back—this serialization dominates runtime.

**Solution:** Use a shared read-only resource (file or database) that workers reference by name, not by copying:

```sql
-- Create a lookup table workers will query directly
CREATE TABLE job_title_categories AS
SELECT DISTINCT job_title_short, 
       CASE 
         WHEN job_title_short LIKE '%Data%' THEN 'Data'
         WHEN job_title_short LIKE '%Engineer%' THEN 'Engineering'
         ELSE 'Other'
       END AS category
FROM job_postings_fact;

CREATE INDEX idx_job_title_short ON job_title_categories(job_title_short);

-- Worker process: connect to DB and enrich only its chunk
-- Pseudo-code: each worker receives only a list of job_ids to process,
-- not the full dataset or lookup table.
-- Worker queries: SELECT j.*, c.category FROM job_postings_fact j
--                 LEFT JOIN job_title_categories c USING (job_title_short)
--                 WHERE j.job_id IN (worker_chunk_ids)
```

By keeping the lookup in the database and passing only job IDs (integers, microscopically small), you eliminate pickle overhead and allow workers to operate independently without data duplication.

## Notes

- **Pickle cost scales with data size:** Pickling a 100MB DataFrame takes ~2–5 seconds; doing this 10 times negates parallelism. Profile with `timeit` on actual data volumes before committing to multiprocessing.
- **Prefer `multiprocessing.Pool` with `chunksize`:** Batching work reduces message frequency. Use `imap_unordered()` instead of `map()` to unblock on slow workers.
- **Connection pooling and state:** Workers cannot share database connections directly; each must create its own. Use context managers to ensure cleanup, or risk resource leaks across process spawning.
- **Testing multiprocessing:** Mock at the function level (unit test worker logic in a single process), then integration-test with `ProcessPoolExecutor` on small datasets. Avoid mocking `Pool` itself—it hides real serialization failures.
- **Adjacent topics:** Threading works better for I/O-bound tasks (no pickling); `concurrent.futures` provides simpler interfaces than raw `multiprocessing`; Dask and Ray abstract away pickling by managing distributed state intelligently.
