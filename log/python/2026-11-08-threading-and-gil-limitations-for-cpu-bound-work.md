---
date: 2026-11-08
phase: python
topic: Threading and GIL: limitations for CPU-bound work
---

# Threading and GIL: limitations for CPU-bound work

*Python for data engineering*

## Concept

Python's Global Interpreter Lock (GIL) allows only one thread to execute Python bytecode at a time, even on multi-core systems. This is a fundamental constraint of CPython's memory management—it uses reference counting, and the GIL protects the refcount updates from race conditions. For I/O-bound work (network requests, file reads, database queries), threading works well because threads release the GIL while waiting. For CPU-bound work (numerical computation, data transformation, parsing), threads provide no speedup and add context-switching overhead instead.

In data pipelines, this matters most during ETL stages where you're tempted to parallelize transformations. If you're cleaning job posting titles, validating salary ranges, or computing aggregate statistics across millions of rows in Python, spawning threads won't help—you'll actually slow down. You need either multiprocessing (separate Python processes, each with its own GIL), async/await (for I/O), or push the computation to vectorized libraries like NumPy and Pandas that release the GIL during their C-level operations.

Without understanding this limitation, engineers write thread pools for CPU work, see no performance gain, and waste time debugging. The fix is recognizing the pattern: if your bottleneck is `compute` not `wait`, use `multiprocessing.Pool` or defer to compiled code (NumPy, SQL, Polars). If it's `wait` (API calls, database queries), threads are fine.

## Practice

**Problem:** You need to validate and enrich 5 million job postings. For each row, you extract the salary range from `salary_year_avg`, check it against industry benchmarks (CPU work), then fetch job category metadata from a slow API (I/O work). A naive approach spawns a thread pool for all work. It will bottleneck on the CPU validation despite the I/O calls.

**Solution:** Separate concerns. Use threads only for I/O (API calls), process CPU work in batches with multiprocessing or vectorized operations.

```python
from concurrent.futures import ThreadPoolExecutor
from multiprocessing import Pool
import pandas as pd

# Validate salary (CPU-bound) — use multiprocessing
def validate_salary_batch(batch: pd.DataFrame) -> pd.DataFrame:
    batch['is_valid_salary'] = (
        (batch['salary_year_avg'] >= 20000) & 
        (batch['salary_year_avg'] <= 500000)
    )
    return batch

# Fetch metadata (I/O-bound) — use threading
def fetch_job_category(job_id: int) -> dict:
    # Simulates slow API call
    return {'job_id': job_id, 'category': 'Tech'}

# Pipeline
df = pd.read_csv('job_postings_fact.csv')

# Split CPU work into chunks, process with multiprocessing
with Pool(processes=4) as pool:
    chunks = [df.iloc[i:i+10000] for i in range(0, len(df), 10000)]
    validated_chunks = pool.map(validate_salary_batch, chunks)
    df = pd.concat(validated_chunks, ignore_index=True)

# I/O work can use threads (GIL is released during network wait)
with ThreadPoolExecutor(max_workers=8) as executor:
    metadata = list(executor.map(fetch_job_category, df['job_id']))

df['category'] = [m['category'] for m in metadata]
```

## Notes

- **Multiprocessing overhead is real:** Spawning processes is expensive. Only use it when CPU work dominates the runtime by >100ms per task; for small operations, vectorize instead.
- **NumPy/Pandas release the GIL:** Operations like `df['salary'].mean()` or `np.array([...]).dot(...)` run in C and release the GIL, so they parallelize naturally without threading.
- **async/await is for I/O:** If you're making 1000 API calls, `asyncio` beats threading (no context-switch overhead) and also avoids the GIL trap by being single-threaded.
- **Profiling first:** Use `cProfile` or `py-spy` to confirm whether you're actually CPU-bound before adding parallelism—most pipelines are I/O-bound.
- **Related:** Understand `concurrent.futures`, `asyncio`, and when to push work to the database (`GROUP BY`, `CASE WHEN`) or data warehouse (Spark, DuckDB) instead of Python.
