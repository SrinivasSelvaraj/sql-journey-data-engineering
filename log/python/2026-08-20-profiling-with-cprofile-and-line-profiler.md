---
date: 2026-08-20
phase: python
topic: Profiling with cProfile and line_profiler
---

# Profiling with cProfile and line_profiler

*Python for data engineering*

## Concept

Profiling identifies where your pipeline actually spends time and memory—not where you *think* it does. Two tools complement each other: **cProfile** shows function-level call counts and cumulative time (useful for finding expensive functions), while **line_profiler** breaks down time line-by-line within a single function (essential for spotting inefficient loops or repeated I/O). In data pipelines, a slow ETL job often isn't the database query or API call you optimized—it's an unnoticed O(n²) loop in your transformation logic, or repeated dataframe copies in pandas. Without profiling, you optimize blind; with it, you make decisions on evidence.

## Practice

**Problem:** A pipeline loads job postings, filters for remote roles, and enriches salary data. It runs slowly. Where is the bottleneck?

```python
# instrument_pipeline.py
import cProfile
import pstats
from line_profiler import LineProfiler

def load_and_filter(job_records: list[dict]) -> list[dict]:
    """Load postings and filter for remote work."""
    filtered = []
    for record in job_records:
        if record.get('job_work_from_home'):
            filtered.append(record)
    return filtered

def enrich_salaries(postings: list[dict]) -> list[dict]:
    """Add salary bands (SLOW: repeated string ops)."""
    for posting in postings:
        sal = posting.get('salary_year_avg', 0)
        # Line-profiler will show this loop is the culprit
        band = 'low' if sal < 50000 else 'mid' if sal < 100000 else 'high'
        posting['salary_band'] = band
    return postings

def profile_pipeline():
    sample_data = [
        {'job_id': i, 'job_work_from_home': i % 2 == 0, 'salary_year_avg': 60000 + i*1000}
        for i in range(10000)
    ]
    
    # cProfile for function-level view
    profiler = cProfile.Profile()
    profiler.enable()
    
    result = load_and_filter(sample_data)
    result = enrich_salaries(result)
    
    profiler.disable()
    stats = pstats.Stats(profiler)
    stats.sort_stats('cumulative').print_stats(10)
    
    # line_profiler for line-by-line in enrich_salaries
    lp = LineProfiler()
    lp.add_function(enrich_salaries)
    lp.enable()
    enrich_salaries(result)
    lp.disable()
    lp.print_stats()

if __name__ == '__main__':
    profile_pipeline()
```

## Notes

- **cProfile overhead is low** (5–10%); run it on production-scale data, not toy samples. `line_profiler` has higher overhead—use it only on specific functions.
- **Premature optimization kills readability.** Profile first, optimize second. A 10× speedup in a function called once matters less than a 2× speedup in a loop called 100,000 times.
- **Memory profiling is separate.** Use `memory_profiler` to catch dataframe copies or unbounded list growth that cProfile won't reveal.
- **Connects to:** unit testing (profile on test data), logging (log slow branches at runtime), and architecture (some slow code can't be optimized—redesign instead).
- **Common trap:** profiling a cold start (cache misses, first imports) instead of steady state. Warm up the pipeline before profiling.
