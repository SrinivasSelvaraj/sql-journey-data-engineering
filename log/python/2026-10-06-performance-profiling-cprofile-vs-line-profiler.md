---
date: 2026-10-06
phase: python
topic: Performance profiling: cProfile vs line_profiler
---

# Performance profiling: cProfile vs line_profiler

*Python for data engineering*

## Concept

**cProfile** measures function call counts and cumulative time across your entire program, identifying which functions consume the most CPU. **line_profiler** measures execution time line-by-line within a single function, revealing which specific statements are bottlenecks. In data pipelines, cProfile answers "where is time being spent across my ETL stages?" while line_profiler answers "why is this transformation function slow?" Use cProfile first to locate the problem function, then line_profiler to fix it. Without profiling, you optimize blind—adding indexes to the wrong table, parallelizing the wrong loop, or pre-fetching data nobody uses.

Both are essential in production pipelines because assumptions about slowness are usually wrong. A query that touches 10 million rows might still be fast if it's well-indexed; a function that processes 100 rows might be slow if it makes redundant network calls inside the loop. Profiling forces you to see what actually happens, not what you think happens.

## Practice

**Problem:** Your daily job posting ingestion pipeline runs in 45 seconds. Marketing says it's blocking their dashboard refresh. You suspect the salary parsing function `normalize_salary()` is slow, but you're not sure if it's the culprit or if the bottleneck is elsewhere (database writes, API calls, data validation).

```sql
-- First, use cProfile to identify the slow function:
-- python -m cProfile -s cumulative ingest_jobs.py 2>&1 | head -30

-- Output shows normalize_salary() takes 22 seconds across 500k calls.
-- Next, profile that function line-by-line with line_profiler:

-- In ingest_jobs.py, add @profile decorator:
# @profile
# def normalize_salary(salary_str, currency='USD'):
#     if not salary_str:
#         return None
#     import re  # ← LINE 1: moved inside function, slow
#     match = re.search(r'(\d+[.,]\d+|\d+)', salary_str)  # ← LINE 2: regex per call
#     if match:
#         return float(match.group(1).replace(',', ''))
#     return None

-- Line profiler output shows LINE 1 and LINE 2 each take ~30µs per call × 500k = 15+ seconds wasted.

-- Solution: Move regex and import outside the loop
import re
SALARY_PATTERN = re.compile(r'(\d+[.,]\d+|\d+)')

def normalize_salary(salary_str, currency='USD'):
    if not salary_str:
        return None
    match = SALARY_PATTERN.search(salary_str)  # ← Reuse compiled pattern
    if match:
        return float(match.group(1).replace(',', ''))
    return None
```

## Notes

- **cProfile overhead:** cProfile itself adds ~40% runtime cost; use `-s cumulative` to sort by total time spent in and below each function, not just direct calls.
- **line_profiler requires decoration:** You must add `@profile` to functions before running `kernprof -l -v ingest_jobs.py`; easy to forget and profile the wrong function.
- **Memory vs. CPU:** Neither tool measures memory consumption well. Use `memory_profiler` (`@profile` + `python -m memory_profiler`) to track peak RAM during large DataFrame operations or batch inserts.
- **Connects to:** database query analysis (EXPLAIN plans), async/concurrency patterns (why profile doesn't catch I/O waits), and type hints (static analysis can catch redundant operations before profiling).
- **Revisit after optimization:** Re-profile after each fix; the bottleneck often shifts to the next slowest function, and diminishing returns kick in quickly.
