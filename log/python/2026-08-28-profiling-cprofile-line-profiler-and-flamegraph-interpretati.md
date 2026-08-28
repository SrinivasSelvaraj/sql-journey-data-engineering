---
date: 2026-08-28
phase: python
topic: Profiling: cProfile, line_profiler and flamegraph interpretation
---

# Profiling: cProfile, line_profiler and flamegraph interpretation

*Python for data engineering*

## Concept

Profiling identifies where your Python code spends time and memory, transforming gut feelings about bottlenecks into measured facts. **cProfile** gives you call counts and cumulative time per function; **line_profiler** shows time spent on individual lines; **flamegraph** visualizes the call stack as a tree, making hot paths obvious at a glance. In data pipelines, profiling is essential because small inefficiencies compound—a 10% overhead in row iteration or JSON parsing can consume hours when processing millions of records. Without profiling, you optimize guesses (often I/O or network when the real culprit is a nested loop or repeated regex compilation), ship slow code to production, and waste compute budget on unnecessary cloud resources.

## Practice

**Problem:** Your job posting ingestion pipeline reads CSV, validates rows, enriches salary data with currency conversion, and writes to a data warehouse. Users report the pipeline takes 45 minutes for 500k rows. You suspect either the currency conversion lookup or the validation logic is slow, but you're not sure.

```python
import cProfile
import pstats
from io import StringIO

# Wrap your pipeline function with cProfile
profiler = cProfile.Profile()
profiler.enable()

# Run your pipeline
load_and_transform_job_postings(csv_path="job_postings.csv", output_table="job_postings_fact")

profiler.disable()

# Print top 10 slowest functions
stats = pstats.Stats(profiler, stream=StringIO())
stats.sort_stats('cumulative')
stats.print_stats(10)

# For line-level detail on the hottest function:
# pip install line_profiler
# kernprof -l -v your_script.py
# Add @profile decorator above the suspect function

@profile
def enrich_salary_with_conversion(rows):
    for row in rows:
        row['salary_year_avg'] = convert_currency(row['salary_currency'], row['salary_raw'])
    return rows

# For flamegraph visualization:
# pip install py-spy
# py-spy record -o profile.svg -- python your_script.py
# Opens interactive SVG showing call hierarchy and time spent in each function
```

## Notes

- **Common mistake:** Profiling only in isolation, not under production-like data volume and concurrency; a function that looks fine on 1k rows may thrash memory on 10M.
- **Decorator overhead matters:** Using `@profile` for line_profiler adds ~5–10% overhead per decorated function; profile selectively.
- **Flamegraph reading:** Wide bars = high cumulative time; tall stacks = deep call chains. Look for repeated patterns (same function called thousands of times) rather than just absolute bar width.
- **Adjacent topic:** Profiling pairs with **benchmarking** (explicit timing of known code paths) and **monitoring** (production observability); profiling is development-time, monitoring is runtime.
- **Revisit:** After optimizing, re-profile to confirm the fix actually moved the needle and didn't create new bottlenecks elsewhere in the call tree.
