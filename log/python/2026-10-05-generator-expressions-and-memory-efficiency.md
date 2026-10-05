---
date: 2026-10-05
phase: python
topic: Generator expressions and memory efficiency
---

# Generator expressions and memory efficiency

*Python for data engineering*

## Concept

A generator expression is a lazy iterator that yields values one at a time instead of building an entire list in memory. Syntax: `(expression for item in iterable)` versus list comprehension `[expression for item in iterable]`. In data engineering pipelines processing millions of rows, generators are critical—loading a CSV with 10M records into a list consumes gigabytes of RAM, while a generator reads one row per iteration. Generators also compose well: you can chain multiple generators without materializing intermediate results, keeping your pipeline memory-flat regardless of dataset size.

Without generators, ETL scripts fail silently or crash on medium-to-large datasets. A naive pipeline reading all rows into memory before transformation becomes undeployable. Generators also enable streaming architectures where data flows continuously through a pipeline without ever fitting whole-dataset into RAM, which is essential for real-time ingestion and unbounded data sources (message queues, APIs, database cursors).

## Practice

**Problem:** Given a CSV file of job postings with 5M+ rows, filter to remote positions posted in the last 30 days, extract relevant fields, and write to a new CSV without loading the entire file into memory.

```python
from datetime import datetime, timedelta
import csv
from typing import Generator, Iterator

def read_jobs(filepath: str) -> Generator[dict, None, None]:
    """Lazily read job postings from CSV, one row at a time."""
    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            yield row

def filter_recent_remote(jobs: Iterator[dict], days: int = 30) -> Generator[dict, None, None]:
    """Filter to remote jobs posted within last N days."""
    cutoff = datetime.now() - timedelta(days=days)
    for job in jobs:
        try:
            posted = datetime.strptime(job['job_posted_date'], '%Y-%m-%d')
            if job['job_work_from_home'] == 'true' and posted >= cutoff:
                yield job
        except (ValueError, KeyError):
            continue  # skip malformed rows

def extract_fields(jobs: Iterator[dict]) -> Generator[dict, None, None]:
    """Project only needed columns."""
    for job in jobs:
        yield {
            'job_id': job['job_id'],
            'job_title': job['job_title_short'],
            'salary': job.get('salary_year_avg', ''),
            'posted': job['job_posted_date']
        }

def pipeline(filepath: str) -> Generator[dict, None, None]:
    """Compose generators without materializing intermediates."""
    jobs = read_jobs(filepath)
    jobs = filter_recent_remote(jobs, days=30)
    jobs = extract_fields(jobs)
    return jobs

# Usage: iterate and write one row at a time
with open('output.csv', 'w', newline='') as out:
    writer = None
    for job in pipeline('jobs.csv'):
        if writer is None:
            writer = csv.DictWriter(out, fieldnames=job.keys())
            writer.writeheader()
        writer.writerow(job)
```

## Notes

- **Iteration exhaustion:** Generators can only be iterated once; after the loop, they're empty. Store results if you need multiple passes, or regenerate.
- **Error handling in generators:** `try/except` inside generator functions silently skips bad rows; log failures explicitly to debug data quality issues.
- **Adjacent topics:** Connects to itertools (chain, groupby), database cursors (inherently lazy), and streaming frameworks (Kafka consumers, pandas chunks).
- **Debugging hazard:** `print(generator)` shows `<generator object>`, not data. Use `next(gen)` or `list(itertools.islice(gen, 5))` for inspection.
- **Type hints:** Annotate with `Generator[YieldType, SendType, ReturnType]` or just `Iterator[T]` for clarity; helps catch composition errors early.
