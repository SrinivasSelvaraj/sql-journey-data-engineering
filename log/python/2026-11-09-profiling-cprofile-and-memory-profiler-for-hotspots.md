---
date: 2026-11-09
phase: python
topic: Profiling: cProfile and memory_profiler for hotspots
---

# Profiling: cProfile and memory_profiler for hotspots

*Python for data engineering*

## Concept

Profiling identifies where your data pipeline actually spends time and memory—not where you *think* it does. cProfile measures function call counts and CPU time; memory_profiler tracks heap usage line-by-line. Without profiling, you optimize the wrong bottleneck: you might spend hours vectorizing a Pandas operation that runs once, while missing a loop that fetches 10,000 API calls serially.

In data engineering, profiling surfaces real costs: does your ETL spike memory loading a CSV, or leak it in a loop? Are you materializing a 2GB intermediate result that could stream? Profiling forces you to see the difference between algorithmic complexity (O(n²) hidden in nested comprehensions) and system behavior (GIL contention, I/O blocking). Without it, you ship pipelines that fail silently under production load or consume 10× more resources than necessary.

## Practice

**Problem:** Your job posting ingestion pipeline reads 500K records, filters by salary threshold, and writes to a fact table. Memory usage peaks at 3GB mid-run despite the dataset being ~800MB on disk. Identify the leak.

```python
import cProfile
import pstats
from io import StringIO
import memory_profiler

@memory_profiler.profile
def ingest_job_postings(csv_path: str, min_salary: int = 50000) -> list[dict]:
    postings = []
    with open(csv_path) as f:
        for line in f:
            record = json.loads(line)
            # BUG: temporary list grows unbounded
            temp_all_records = [record] + temp_all_records if 'temp_all_records' in locals() else [record]
            
            if record['salary_year_avg'] and record['salary_year_avg'] >= min_salary:
                postings.append(record)
    return postings

# Profile CPU hotspots
pr = cProfile.Profile()
pr.enable()
result = ingest_job_postings('jobs.jsonl', min_salary=75000)
pr.disable()

s = StringIO()
ps = pstats.Stats(pr, stream=s).sort_stats('cumulative')
ps.print_stats(10)
print(s.getvalue())

# Output: memory_profiler line-by-line shows temp_all_records accumulating
```

**Fixed version:**
```python
@memory_profiler.profile
def ingest_job_postings(csv_path: str, min_salary: int = 50000) -> list[dict]:
    postings = []
    with open(csv_path) as f:
        for line in f:
            record = json.loads(line)
            # Filter in-place; never materialize full dataset
            if record['salary_year_avg'] and record['salary_year_avg'] >= min_salary:
                postings.append(record)
    return postings
```

## Notes

- **Premature optimization trap:** Profile before refactoring. Sorting by salary before filtering can halve memory if salary is sparse; you won't know without data.
- **GIL and I/O:** cProfile counts time but can't show I/O wait. If your pipeline fetches job postings from an API, the bottleneck is network latency, not CPU—profile I/O with tools like `py-spy` or async profilers.
- **Memory_profiler overhead:** Running with `@profile` decorator adds 10–20% overhead; use it on suspect functions, not entire pipelines. For production, sample or use `tracemalloc` for snapshots.
- **Generator vs. list:** If you see memory spike at "load CSV," you're likely materializing a list. Replace with generators (`yield` instead of `append()`) to stream through large datasets.
- **Connects to:** typing (catch schema mismatches before they blow up memory), testing (profile your test fixtures—if tests use full datasets, they'll hide production bottlenecks), and async design (profiling reveals if parallelization actually helps).
