---
date: 2026-10-26
phase: python
topic: Profiling CPU and memory in production
---

# Profiling CPU and memory in production

*Python for data engineering*

## Concept

Production profiling reveals where your pipeline actually spends time and memory—not where you *think* it does. CPU profiling identifies hot functions and loops; memory profiling catches leaks, bloat from large intermediate objects, and inefficient data structures. Without profiling, you optimize blind spots while real bottlenecks remain invisible. In data pipelines especially, a single unoptimized join or unclosed file handle can cascade into OOM failures or timeouts that only manifest under full-scale data loads, not in local testing.

Profiling becomes critical when you move from development to production because scale reveals sins: a function that's fine on 10K rows might thrash on 100M. You need tools like `cProfile` (CPU), `memory_profiler` (line-by-line memory), and `tracemalloc` (allocation traces) baked into your pipeline observability, not bolted on after failure. The goal is to quantify trade-offs—does caching that extra dataframe save CPU but blow memory? Can you stream instead of loading everything?

## Practice

**Problem:** A job posting ETL processes 5M rows daily. The pipeline loads all postings into memory, filters by location and salary, then writes results. Recently it started timing out in production and occasionally hitting memory limits, but runs fine locally on test data (10K rows). You need to identify whether the bottleneck is CPU-bound parsing/filtering or memory-bound from holding the full dataset.

```sql
-- Profile memory and CPU by instrumenting the Python pipeline
import cProfile
import pstats
import io
import tracemalloc
from memory_profiler import profile

@profile  # decorator logs line-by-line memory usage
def process_job_postings(csv_path: str) -> pd.DataFrame:
    df = pd.read_csv(csv_path)  # watch: is this the memory spike?
    df = df[df['salary_year_avg'] > 50000]
    df = df[df['job_work_from_home'] == True]
    return df

# Wrap main ETL with cProfile to find CPU hotspots
pr = cProfile.Profile()
pr.enable()

result = process_job_postings('job_postings.csv')
result.to_parquet('output.parquet')

pr.disable()
s = io.StringIO()
ps = pstats.Stats(pr, stream=s).sort_stats('cumulative')
ps.print_stats(10)  # top 10 functions by cumulative time
print(s.getvalue())

# Snapshot memory before and after to catch leaks
tracemalloc.start()
result = process_job_postings('job_postings.csv')
current, peak = tracemalloc.get_traced_memory()
print(f"Current: {current / 1e6:.1f}MB; Peak: {peak / 1e6:.1f}MB")
tracemalloc.stop()

# Solution: stream instead of loading all rows
def process_job_postings_streaming(csv_path: str, chunk_size: int = 50000):
    chunks = []
    for chunk in pd.read_csv(csv_path, chunksize=chunk_size):
        chunk = chunk[(chunk['salary_year_avg'] > 50000) & 
                      (chunk['job_work_from_home'] == True)]
        chunks.append(chunk)
    return pd.concat(chunks, ignore_index=True)
```

## Notes

- **Premature optimization is real, but invisible bottlenecks are worse.** Profile first on realistic data size, then optimize the actual top-3 time consumers—not hunches.
- **Memory profiling is often more urgent than CPU in data pipelines.** A single unfiltered dataframe or unclosed file handle scales linearly; CPU gains from vectorization matter less if you OOM first.
- **Chunking and streaming are your friends.** If profiling shows memory is the constraint, move from load-all-then-process to read-filter-write loops; if CPU dominates, consider vectorization (pandas over loops) or parallelization (multiprocessing with profiling per worker).
- **Profile under production conditions.** Test data size, row width, and external I/O latency all affect which bottleneck appears. A 10K-row test won't expose memory fragmentation from 5M rows.
- **Connect profiling to logging and alerting.** Log peak memory and top functions at pipeline start; trigger alerts if peak memory exceeds threshold or a normally-fast function slows down—early warning of data skew or degradation.
