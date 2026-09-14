---
date: 2026-09-14
phase: python
topic: Itertools recipes: groupby, islice, cycle combinations
---

# Itertools recipes: groupby, islice, cycle combinations

*Python for data engineering*

## Concept

`itertools.groupby`, `islice`, and `cycle` solve real pipeline problems when processing large datasets without materializing everything in memory. `groupby` clusters consecutive equal elements (critical for sorted data streams); `islice` windows or truncates iterators without loading into lists; `cycle` repeats a finite iterator endlessly for round-robin patterns. These matter in ETL because data often arrives sorted by date or category, and you need to aggregate, batch, or distribute records without breaking into pandas/polars. Without them, you either load entire result sets (memory blowout on 100M rows) or write nested loops that are fragile to schema changes. Type hints + defensive input validation transform these from "cute functional tricks" into production code that survives malformed timestamps and missing groups.

## Practice

**Problem:** Given a job_postings_fact table, find the average salary for each job_title_short, but only for jobs posted in the last 30 days, and return results in batches of 5 titles (for paginated API responses). You cannot assume the table is already sorted.

```sql
WITH recent_jobs AS (
  SELECT job_title_short, salary_year_avg
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
    AND salary_year_avg IS NOT NULL
),
title_stats AS (
  SELECT job_title_short, AVG(salary_year_avg) as avg_salary, COUNT(*) as count
  FROM recent_jobs
  GROUP BY job_title_short
  ORDER BY job_title_short
),
ranked AS (
  SELECT job_title_short, avg_salary, count,
         ROW_NUMBER() OVER (ORDER BY job_title_short) as rn
  FROM title_stats
)
SELECT job_title_short, avg_salary, count,
       CEIL(rn::FLOAT / 5) as batch_id
FROM ranked
ORDER BY batch_id, job_title_short;
```

Python companion (using itertools):
```python
from itertools import groupby, islice
from typing import Iterator, Tuple
from datetime import datetime, timedelta

def batch_salary_stats(
    rows: Iterator[dict], 
    batch_size: int = 5
) -> Iterator[list[dict]]:
    """Yield batches of title salary aggregates from sorted rows."""
    # Expect rows sorted by job_title_short, already filtered by date
    batch = []
    for title, group in groupby(rows, key=lambda r: r['job_title_short']):
        salaries = [r['salary_year_avg'] for r in group if r['salary_year_avg']]
        if not salaries:
            continue
        batch.append({
            'job_title_short': title,
            'avg_salary': sum(salaries) / len(salaries),
            'count': len(salaries)
        })
        if len(batch) == batch_size:
            yield batch
            batch = []
    if batch:
        yield batch

# Usage: consume in pages without loading entire result
for page in batch_salary_stats(db_cursor.fetchall(), batch_size=5):
    send_to_api(page)
```

## Notes

- **groupby pitfall:** It returns an iterator of (key, group_iter) pairs; the group_iter is exhausted after moving to the next key. Materialize with `list(group)` if you need to iterate twice.
- **islice + cycle pattern:** Use `cycle(pattern)` with `zip(islice(...), cycle(...))` for round-robin assignment (e.g., distributing jobs across N workers), not for infinite loops in production.
- **Type hints matter here:** `Iterator[dict]` signals that you *cannot* index or rewind; forces callers to pipeline correctly and catches eager-load bugs early.
- **Sort order is implicit:** `groupby` only clusters *consecutive* equal keys—unsorted input silently produces wrong results. Always add an explicit `ORDER BY` in SQL or `.sort_key()` in Python.
- **Adjacent skills:** Combines with `functools.reduce` for fold operations, `operator.itemgetter` for cleaner key functions, and SQL window functions (`ROW_NUMBER`, `LAG/LEAD`) for complex grouping without Python.
