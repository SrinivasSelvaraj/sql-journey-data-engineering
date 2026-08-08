---
date: 2026-08-08
phase: python
topic: Iterators, generators and streaming large files
---

# Iterators, generators and streaming large files

*Python for data engineering*

## Concept

Iterators and generators enable processing of data that doesn't fit in memory by yielding one item at a time rather than building entire collections. A generator is a function with `yield` statements that returns an iterator—it computes values lazily, pausing execution until the next value is requested. This is critical for data pipelines: a 10GB CSV file cannot load into RAM all at once, but a generator can read it line-by-line, transform each record, and pass it downstream.

Without generators, you'd load entire datasets into lists, causing out-of-memory errors on large files and pipelines that stall while waiting for full materialization. Generators keep memory footprint constant and enable true streaming: data flows through the pipeline continuously rather than in batch phases. They also compose elegantly—one generator feeds another, creating a chain of lightweight transformations.

## Practice

**Problem:** You need to load a large job postings CSV file, filter for remote data engineering roles earning >$120k, deduplicate by job_id, and write results to a database. The file is too large to load entirely.

```python
import csv
from typing import Iterator, Set
from datetime import datetime

def read_csv_streaming(filepath: str) -> Iterator[dict]:
    """Stream CSV rows as dicts without loading entire file."""
    with open(filepath, mode='r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            yield row

def filter_remote_high_pay(rows: Iterator[dict], min_salary: int = 120000) -> Iterator[dict]:
    """Filter for remote roles with salary threshold."""
    for row in rows:
        salary = int(row.get('salary_year_avg', 0) or 0)
        is_remote = row.get('job_work_from_home', '').lower() == 'true'
        if is_remote and salary >= min_salary and 'data engineer' in row.get('job_title_short', '').lower():
            yield row

def deduplicate_by_id(rows: Iterator[dict]) -> Iterator[dict]:
    """Deduplicate by job_id, keeping first occurrence."""
    seen: Set[str] = set()
    for row in rows:
        job_id = row['job_id']
        if job_id not in seen:
            seen.add(job_id)
            yield row

# Usage: composable pipeline
pipeline = deduplicate_by_id(
    filter_remote_high_pay(
        read_csv_streaming('job_postings.csv')
    )
)

# Consume iterator in database insert
for record in pipeline:
    # insert_to_db(record)
    print(record)
```

## Notes

- **Memory leak in deduplication:** `deduplicate_by_id` stores all seen IDs in a set; for truly massive files, use an external bloom filter or database query instead of in-memory state.
- **Generator exhaustion:** Iterators can only be consumed once; if you iterate twice over the same generator, the second pass yields nothing. Save to a list or regenerate if you need multiple passes.
- **Type hints matter:** `Iterator[dict]` signals that a function streams data; this is critical for pipeline clarity and catches misuse during type-checking.
- **Adjacent: context managers & cleanup.** Generators often open file handles; use `with` statements or ensure `finally` blocks close resources, or generators may leak file descriptors.
- **Revisit: itertools module.** Functions like `itertools.chain()`, `islice()`, and `groupby()` are built for composing generators; they keep memory flat and are faster than hand-rolled loops.
