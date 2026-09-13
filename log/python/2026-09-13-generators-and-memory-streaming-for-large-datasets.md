---
date: 2026-09-13
phase: python
topic: Generators and memory streaming for large datasets
---

# Generators and memory streaming for large datasets

*Python for data engineering*

## Concept

Generators are Python functions that use `yield` instead of `return`, producing values one at a time rather than materializing entire collections in memory. For data engineering, they are essential when processing datasets larger than available RAM—reading a 10GB CSV file into a list will crash, but a generator can yield rows indefinitely without holding more than one (or a small buffer) in memory at once.

Memory streaming matters because it decouples data volume from memory constraints. Without generators, you'd need to batch manually, lose the ability to pipeline transformations, or resort to external tools. A generator-based ETL can chain `map(transform) → filter(validate) → map(enrich)` operations lazily, executing them only when a consumer (like a database writer) pulls data.

Generators break when you need random access, multiple passes over data, or to know the dataset length upfront. They're also fragile to exceptions mid-stream—if transformation fails on row 50,000, you may lose progress without checkpointing.

## Practice

**Problem:** Load 2M job postings from CSV, filter those with salary data, enrich job titles to title case, and yield only remote positions. Using a generator to avoid loading the full file into memory.

```python
import csv
from typing import Generator, TypedDict

class JobPosting(TypedDict):
    job_id: int
    job_title_short: str
    salary_year_avg: int | None
    job_work_from_home: bool
    job_posted_date: str
    job_location: str

def stream_job_postings(filepath: str) -> Generator[JobPosting, None, None]:
    """Stream job postings from CSV, yield only remote positions with salary."""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row_num, row in enumerate(reader, start=2):  # start=2 for 1-indexed header
                try:
                    # Validate and transform
                    salary = row.get('salary_year_avg', '').strip()
                    if not salary or salary == 'NULL':
                        continue  # Skip rows without salary
                    
                    job_posting: JobPosting = {
                        'job_id': int(row['job_id']),
                        'job_title_short': row['job_title_short'].title(),
                        'salary_year_avg': int(salary),
                        'job_work_from_home': row['job_work_from_home'].lower() == 'true',
                        'job_posted_date': row['job_posted_date'],
                        'job_location': row['job_location'],
                    }
                    
                    # Filter: remote only
                    if job_posting['job_work_from_home']:
                        yield job_posting
                        
                except (ValueError, KeyError) as e:
                    print(f"Skipping row {row_num}: {e}")
                    continue
    except FileNotFoundError as e:
        raise FileNotFoundError(f"Job postings file not found: {filepath}") from e

# Usage: iterate without loading file
for posting in stream_job_postings('job_postings.csv'):
    print(f"Remote: {posting['job_title_short']} — ${posting['salary_year_avg']:,}")
```

## Notes

- **Generators are lazy and single-pass**: Once exhausted, they're empty. If you need to iterate twice, convert to a list (defeats the purpose) or recreate the generator.
- **Exception handling mid-stream**: Errors don't fail the whole pipeline—use try/except in the generator and log skipped rows. Without it, one malformed row crashes the entire ETL.
- **Type hints with generators**: Use `Generator[YieldType, SendType, ReturnType]`. For data pipelines, it's almost always `Generator[T, None, None]`.
- **Checkpointing and recovery**: For production, track row offsets or line numbers so failed runs can resume. Generators alone don't offer this—pair with a state tracker or database cursor.
- **Adjacent topics**: Connect this to itertools (chain, islice), context managers (ensure file cleanup), and async generators for I/O-bound operations.
