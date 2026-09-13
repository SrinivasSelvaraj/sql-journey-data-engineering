---
date: 2026-09-13
phase: python
topic: CPU flame graphs and cProfile interpretation
---

# CPU flame graphs and cProfile interpretation

*Python for data engineering*

## Concept

CPU flame graphs visualize where your Python process spends time by stacking function calls horizontally (wider = more CPU time). `cProfile` is Python's built-in profiler that instruments function calls and measures wall time; the output feeds into flame graph tools like `flamegraph.py` or interactive viewers. This matters in data pipelines because a slow ETL job might appear to hang at one step when the real bottleneck is buried three function calls deep—a flame graph shows you the call stack, not just total time.

Without profiling, you waste days optimizing the wrong code. A 10-line DataFrame transformation might call an O(n²) distance calculation inside a groupby. You'll also miss inefficiencies like repeated I/O inside tight loops or excessive memory allocation in vectorized operations that look fast in benchmarks but stall under production scale.

## Practice

**Problem:** Your pipeline loads `job_postings_fact`, groups by job location, and computes average salary for each location. The query runs fine on 100K rows but crawls at 10M rows, blocking downstream processes. Profile the transformation step to identify whether time is spent in SQL execution, Python deserialization, or aggregation logic.

```sql
-- Wrapped in Python with cProfile instrumentation
import cProfile
import pstats
from io import StringIO
import pandas as pd
import sqlalchemy as sa

def profile_job_location_aggregation(connection_string: str) -> pd.DataFrame:
    engine = sa.create_engine(connection_string)
    query = """
    SELECT 
        job_location,
        AVG(salary_year_avg) as avg_salary,
        COUNT(*) as job_count
    FROM job_postings_fact
    WHERE salary_year_avg IS NOT NULL
    GROUP BY job_location
    ORDER BY avg_salary DESC
    """
    df = pd.read_sql(query, engine)
    return df

# Profile the execution
profiler = cProfile.Profile()
profiler.enable()
result = profile_job_location_aggregation("postgresql://user:pass@localhost/jobs_db")
profiler.disable()

# Print results
stats = pstats.Stats(profiler, stream=StringIO())
stats.sort_stats("cumulative")
stats.print_stats(20)  # Top 20 functions by cumulative time
```

The flame graph output will show whether time concentrates in `read_sql()` (DB connection/query), pandas internal operations (dtype inference, sorting), or your aggregation logic. If DB dominates, push the GROUP BY lower. If deserialization dominates, switch to Polars or Arrow. If Python aggregation dominates, you're likely doing something wrong.

## Notes

- **cProfile overhead**: Instrumentation adds 10–50% overhead; use it for relative comparison, not absolute timing. Run multiple times to filter noise.
- **Flame graph reading**: Wider boxes = more time. Look for unexpected widths (like `__init__` consuming 30% of a loop's runtime). Tall stacks suggest deep call chains; often a sign of inefficient recursion or decorator chains.
- **Connects to**: memory profiling (`memory_profiler`, `pympler`), async profiling (different tools needed for asyncio), and query explain plans—the SQL equivalent of flame graphs.
- **Common mistake**: Optimizing the wrong layer. A 2× faster groupby doesn't help if 80% of time is `read_sql()`. Profile *before* refactoring.
- **Revisit**: Profiling in production (sampling profilers like `py-spy`, continuous profiling tools) and relating CPU profiles to I/O wait time (use `strace` or APM tools to see the full story).
