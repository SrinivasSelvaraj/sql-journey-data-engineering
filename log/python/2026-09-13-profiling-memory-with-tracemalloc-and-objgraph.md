---
date: 2026-09-13
phase: python
topic: Profiling memory with tracemalloc and objgraph
---

# Profiling memory with tracemalloc and objgraph

*Python for data engineering*

## Concept

Memory profiling with `tracemalloc` and `objgraph` is essential when building data pipelines that process large datasets or run continuously. `tracemalloc` captures memory allocations at the Python level, letting you identify which lines of code consume the most heap memory; `objgraph` visualizes object references and detects memory leaks by tracking what's keeping objects alive. Without profiling, pipelines silently grow memory footprint over time—a 100 MB leak per day becomes a crash after two weeks of production runs. This matters most when your code loads entire tables into memory, applies transformations iteratively, or caches intermediate results. The difference between a pipeline that processes 10 GB in 2 GB of RAM versus one that tries to use 12 GB is the difference between scaling horizontally and getting paged to death.

## Practice

**Problem:** A pipeline loads job postings into a DataFrame, enriches each row with external API calls, and caches results. After processing 500k rows, memory use jumps from 1 GB to 8 GB unexpectedly.

```python
import tracemalloc
import pandas as pd

tracemalloc.start()

# Simulate pipeline
df = pd.read_parquet('job_postings_fact.parquet')
cache = {}

for idx, row in df.iterrows():
    job_id = row['job_id']
    # BUG: caching the entire row (and DataFrame reference)
    cache[job_id] = row
    # Process...

current, peak = tracemalloc.get_traced_memory()
print(f"Peak: {peak / 1024 / 1024:.1f} MB")

# Solution: cache only what you need
tracemalloc.reset_peak()
cache = {}

for idx, row in df.iterrows():
    job_id = row['job_id']
    # Store only relevant fields
    cache[job_id] = {
        'title': row['job_title_short'],
        'salary': row['salary_year_avg']
    }

current, peak = tracemalloc.get_traced_memory()
print(f"Peak after fix: {peak / 1024 / 1024:.1f} MB")
tracemalloc.stop()
```

## Notes

- **Circular references are invisible to `del`:** if object A holds a reference to B and B holds a reference to A, both stay in memory even after `del a`. Use `objgraph.show_refs([obj])` to visualize these chains and refactor to break cycles before objects go out of scope.

- **DataFrames copy on iteration:** calling `.iterrows()` creates a new Series object for each row; use `.itertuples()` or vectorized operations instead for 2–5× memory savings on large tables.

- **Generator functions are your friend:** replace list comprehensions that build intermediate results with generators (`yield` instead of `append`); this defers allocation until values are actually consumed.

- **Profile in production-like conditions:** memory leaks often only appear under realistic data volume and concurrency. Run `tracemalloc` or `memory_profiler` against your actual test dataset before deployment.

- **Connect to resource limits:** pair profiling with logging and alerting thresholds (e.g., trigger a warning at 80% of pod memory) so you catch creeping leaks before they cause crashes; document expected peak memory for each pipeline stage.
