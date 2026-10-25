---
date: 2026-10-25
phase: python
topic: Generator expressions and memory-efficient streaming
---

# Generator expressions and memory-efficient streaming

*Python for data engineering*

## Concept

Generator expressions (`(x for x in iterable)`) and the `yield` keyword defer computation until values are actually needed, processing one item at a time instead of loading entire datasets into memory. This is critical in data pipelines where you might filter millions of rows, transform log files, or stream API responses—materializing everything upfront wastes RAM and crashes on large inputs.

Without generators, a pipeline that reads a 10 GB CSV, filters it, transforms it, and writes it requires holding intermediate lists in memory. With generators, each row flows through the chain as a single object, then is discarded. The memory footprint becomes constant rather than proportional to dataset size.

Generators also enable *lazy evaluation*: you only compute values you actually consume. If your pipeline stops early (e.g., finding the first matching record), generator expressions never process the rest. This pattern is foundational for resilient ETL code that survives bad input—you validate and transform one record at a time, catching errors before they corrupt state.

## Practice

**Problem:** You have a `job_postings_fact` table with 5 million rows. You need to extract and validate remote full-time jobs with salary > $120k posted in the last 30 days, then write them to a parquet file. Reading all 5M rows into a list before filtering wastes memory; a single bad salary value should not crash the entire pipeline.

```sql
WITH filtered_jobs AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location
  FROM job_postings_fact
  WHERE job_work_from_home = TRUE
    AND salary_year_avg > 120000
    AND job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
)
SELECT * FROM filtered_jobs;
```

**Python pipeline with generators:**

```python
import pandas as pd
from typing import Generator
from datetime import datetime, timedelta

def validate_job_record(row: dict) -> dict | None:
    """Validate a single job record; return None if invalid."""
    try:
        if not isinstance(row.get('salary_year_avg'), (int, float)) or row['salary_year_avg'] <= 0:
            return None
        if row.get('job_work_from_home') is not True:
            return None
        return row
    except (KeyError, TypeError):
        return None

def stream_remote_high_salary_jobs(
    query_result: pd.DataFrame,
    min_salary: int = 120000,
    days_back: int = 30
) -> Generator[dict, None, None]:
    """Yield valid remote jobs with high salary, one at a time."""
    cutoff_date = datetime.now().date() - timedelta(days=days_back)
    
    for _, row in query_result.iterrows():
        record = row.to_dict()
        
        # Validate and filter
        if record.get('job_posted_date', pd.NaT).date() < cutoff_date:
            continue
        if record.get('salary_year_avg', 0) < min_salary:
            continue
        
        validated = validate_job_record(record)
        if validated:
            yield validated

# Usage: never loads all rows into memory
df = pd.read_sql("SELECT * FROM job_postings_fact LIMIT 10000", conn)
jobs_gen = stream_remote_high_salary_jobs(df)

# Write to parquet one batch at a time
batch = []
for job in jobs_gen:
    batch.append(job)
    if len(batch) == 1000:
        pd.DataFrame(batch).to_parquet('remote_jobs.parquet', append=True)
        batch.clear()
if batch:
    pd.DataFrame(batch).to_parquet('remote_jobs.parquet', append=True)
```

## Notes

- **Generator vs. list comprehension:** `(x for x in data)` is lazy; `[x for x in data]` is eager. Use generators in pipelines; use list comprehensions only when you need the full result immediately or it's small.
- **Error handling per record:** Validate inside the generator so one bad row doesn't kill the entire batch. Return `None` or `yield` nothing for invalid records, then filter downstream.
- **Adjacent topics:** Connects to itertools (chain, groupby, islice for windowing), context managers (for safe file/connection handling), and type hints with `Generator[YieldType, SendType, ReturnType]` for clarity.
- **Common mistake:** Mixing generator logic with side effects (writing to database inside the generator). Generators should be pure; perform I/O in the consuming loop.
- **Revisit:** Async generators (`async def`, `async for`) for concurrent API calls; `functools.reduce` for stateful streaming aggregations; how pandas `.iterrows()` and `.itertuples()` compare to raw generators on performance.
