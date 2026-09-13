---
date: 2026-09-13
phase: python
topic: Collections.namedtuple and dataclass memory overhead
---

# Collections.namedtuple and dataclass memory overhead

*Python for data engineering*

## Concept

`namedtuple` and `dataclass` both provide structured data containers with type hints and cleaner syntax than plain tuples or dicts, but they have different memory footprints. `namedtuple` is immutable and lightweight—it creates instances that are just optimized tuples under the hood, making it ideal for large collections of records in ETL pipelines. `dataclass` is mutable by default, more flexible, and includes automatic `__init__`, `__repr__`, and `__eq__` methods, but consumes more memory due to instance `__dict__` overhead unless you use `slots=True` (Python 3.10+).

In data pipelines processing millions of rows, this matters. If you're holding 10M job posting records in memory before writing to a warehouse, choosing `namedtuple` over a plain `dataclass` can cut memory usage by 40–50%. Conversely, if you need to mutate fields during transformation or validate data on assignment, `dataclass` with validation hooks is worth the overhead. Without picking the right structure, pipelines fail silently with OOM errors on production data, or become unmaintainably fragile because untyped dicts offer no IDE autocomplete or runtime checks.

## Practice

**Problem:** You're building an ETL pipeline that reads job postings from an API, enriches them with salary data, and batches them for insertion. You need type safety, memory efficiency for 5M records, and immutability to prevent accidental mutations during transformation.

```python
from collections import namedtuple
from datetime import date

# Lightweight, immutable, memory-efficient
JobPosting = namedtuple(
    'JobPosting',
    ['job_id', 'job_title_short', 'salary_year_avg', 'job_work_from_home', 'job_posted_date', 'job_location']
)

# Usage in pipeline
raw_records = fetch_from_api()  # returns dicts
postings = [
    JobPosting(
        job_id=r['id'],
        job_title_short=r['title'],
        salary_year_avg=r.get('salary'),
        job_work_from_home=r['remote'],
        job_posted_date=date.fromisoformat(r['posted']),
        job_location=r['location']
    )
    for r in raw_records
]

# Type-safe, IDE-aware access
batch = postings[0:1000]
for posting in batch:
    insert_into_warehouse(posting.job_id, posting.salary_year_avg)
```

## Notes

- **namedtuple immutability is a feature, not a limitation**: in pipelines, immutable records prevent bugs where downstream code accidentally modifies shared state; if you need to transform data, create a new namedtuple rather than mutating.
- **dataclass with `slots=True`** (3.10+) closes the memory gap and adds mutability—use this if you need validation logic or field modification during transformation steps.
- **Don't use plain dicts for structured data in pipelines**: they work but offer zero type checking, no IDE support, and are verbose when passed between functions; a namedtuple is always better.
- **Serialization matters**: namedtuples serialize cleanly to JSON (convert via `._asdict()`) and are compatible with most data warehouse clients; dataclasses require extra boilerplate unless you use `asdict()` and a custom encoder.
- **Revisit when adding validation**: if your pipeline grows to include field constraints (e.g., salary > 0, location not null), migrate to `dataclass` with `__post_init__` or pydantic `BaseModel` for stronger guarantees.
