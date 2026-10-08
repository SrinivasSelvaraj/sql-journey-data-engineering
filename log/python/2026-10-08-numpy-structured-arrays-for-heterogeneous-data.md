---
date: 2026-10-08
phase: python
topic: Numpy structured arrays for heterogeneous data
---

# Numpy structured arrays for heterogeneous data

*Python for data engineering*

## Concept

Numpy structured arrays allow you to store heterogeneous data (mixed types) in a single contiguous array, where each row is a record with named fields. This is essential in data pipelines because raw input often mixes integers, floats, strings, and booleans—pandas DataFrames are more flexible but carry overhead; structured arrays offer speed, memory efficiency, and schema enforcement when you need to validate and transform data before loading.

Without structured arrays, you either cast everything to object dtype (slow, defeats Numpy's vectorization) or split data into separate arrays and lose track of which columns belong together. When a CSV has 50 columns of mixed types and you need to filter, validate, and reshape millions of rows, untyped lists or generic dicts become unmaintainable and fail silently on type mismatches.

Structured arrays force you to declare your schema upfront. This catches schema drift early—if a field suddenly contains a string where you expect an integer, the array creation fails loudly rather than corrupting downstream logic.

## Practice

**Problem:** Parse job posting CSV with mixed types (IDs as int, salary as float, dates as strings, remote flags as booleans). Validate that salary ≥ 0 and dates parse correctly, then filter to remote jobs in the US before inserting into a fact table.

```python
import numpy as np
from datetime import datetime

# Define structured array dtype
job_posting_dtype = np.dtype([
    ('job_id', 'i4'),                    # 32-bit integer
    ('job_title_short', 'U50'),          # Unicode string, max 50 chars
    ('salary_year_avg', 'f8'),           # 64-bit float
    ('job_work_from_home', '?'),         # Boolean
    ('job_posted_date', 'U10'),          # String 'YYYY-MM-DD'
    ('job_location', 'U30')              # Unicode string
])

# Raw data (e.g., from CSV)
raw_data = [
    (1, 'Data Engineer', 95000.0, True, '2024-01-15', 'Remote'),
    (2, 'Analyst', -5000.0, False, '2024-01-16', 'New York'),
    (3, 'Senior Engineer', 150000.0, True, '2024-01-17', 'Remote'),
]

# Create structured array with validation
def load_and_validate(raw_rows):
    validated = []
    for row in raw_rows:
        job_id, title, salary, remote, date_str, location = row
        
        # Validate salary
        if salary < 0:
            raise ValueError(f"Job {job_id}: negative salary {salary}")
        
        # Validate date format
        try:
            datetime.strptime(date_str, '%Y-%m-%d')
        except ValueError:
            raise ValueError(f"Job {job_id}: invalid date {date_str}")
        
        validated.append((job_id, title, salary, remote, date_str, location))
    
    return np.array(validated, dtype=job_posting_dtype)

jobs = load_and_validate(raw_data)

# Filter: remote jobs
remote_jobs = jobs[jobs['job_work_from_home'] == True]

# Insert into fact table (pseudo-code)
for record in remote_jobs:
    insert_job_posting_fact(
        job_id=int(record['job_id']),
        job_title_short=record['job_title_short'].strip(),
        salary_year_avg=float(record['salary_year_avg']),
        job_work_from_home=bool(record['job_work_from_home']),
        job_posted_date=record['job_posted_date'],
        job_location=record['job_location'].strip()
    )
```

## Notes

- **Unicode string sizes are fixed**: `'U50'` allocates 50 characters per field; truncation happens silently if you exceed it. Plan string widths conservatively or validate input length before insertion.
- **Dates as strings, not native**: Numpy has no native date dtype for structured arrays; store as `'U10'` and parse in Python or SQL. This trades query speed for schema clarity.
- **Connects to**: Pydantic models (for validation before array creation), Parquet schemas (which enforce similar field typing), and Apache Arrow (which uses similar columnar type systems).
- **Mistake**: Assuming structured arrays are faster than DataFrames for all workflows; they excel at bulk validation and filtering, but lack the groupby/join flexibility that makes pandas indispensable later in the pipeline.
- **Revisit**: Using `np.genfromtxt()` with `dtype=job_posting_dtype` to load CSV directly, and comparing memory footprint (structured array vs. DataFrame) on real datasets.
