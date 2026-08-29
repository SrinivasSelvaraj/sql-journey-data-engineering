---
date: 2026-08-29
phase: python
topic: Duck typing vs explicit interfaces in dynamic Python
---

# Duck typing vs explicit interfaces in dynamic Python

*Python for data engineering*

## Concept

Duck typing—"if it walks like a duck and quacks like a duck, it's a duck"—lets Python code accept any object with the required methods, regardless of declared type. This is powerful for data pipelines: a function can accept a file-like object, a database cursor, or a pandas DataFrame without caring about the actual class. However, in production pipelines handling millions of records, implicit contracts become dangerous. When a CSV reader expects `read()` but receives an object without it, you discover the error at runtime—after processing half your data.

Explicit interfaces (via type hints, protocols, or ABC base classes) force clarity upfront. They document expected behavior, catch mismatches before execution, and make refactoring safer. For data engineering, this means: a function that transforms a batch of records should declare what attributes those records must have; a function that writes to storage should specify the interface it needs from a writer object.

The trade-off matters most when pipelines run unsupervised (scheduled jobs, cloud functions) and when bad input is expensive to debug. Duck typing wins for exploratory notebooks; explicit interfaces win for production code that survives missing columns, unexpected null values, or schema changes.

## Practice

**Problem:** You are building a pipeline that extracts job postings from multiple sources (API, CSV, database). Each source returns records differently—some as dicts, some as named tuples, some as custom objects. Your `enrich_salary()` function needs to accept any of these, validate that `salary_year_avg` exists and is numeric, and return a consistent record. Without explicit interfaces, you won't know which source is broken until the pipeline fails mid-run.

**Solution:**

```python
from typing import Protocol, TypeVar, Any
from dataclasses import dataclass

class JobPostingRecord(Protocol):
    """Explicit interface: any object with these attributes works."""
    job_id: int
    job_title_short: str
    salary_year_avg: float | None
    job_work_from_home: bool
    job_posted_date: str
    job_location: str

T = TypeVar('T', bound=JobPostingRecord)

def enrich_salary(record: T) -> T:
    """Accepts any object matching JobPostingRecord protocol."""
    if not hasattr(record, 'salary_year_avg'):
        raise ValueError(f"Record missing salary_year_avg: {record}")
    
    if record.salary_year_avg is not None and not isinstance(record.salary_year_avg, (int, float)):
        raise TypeError(f"salary_year_avg must be numeric, got {type(record.salary_year_avg)}")
    
    return record

@dataclass
class JobPosting:
    job_id: int
    job_title_short: str
    salary_year_avg: float | None
    job_work_from_home: bool
    job_posted_date: str
    job_location: str

# All these work with enrich_salary() because they match the protocol:
record1 = JobPosting(1, "Data Engineer", 120000.0, True, "2024-01-15", "Remote")
record2 = {"job_id": 2, "job_title_short": "Analyst", "salary_year_avg": None, "job_work_from_home": False, "job_posted_date": "2024-01-16", "job_location": "NYC"}
record3 = type('Record', (), {k: v for k, v in record1.__dict__.items()})()

# Type checker validates this; runtime catches missing attributes:
enrich_salary(record1)  # ✓ OK
enrich_salary(record2)  # ✗ Runtime error: dict doesn't have attributes (use TypedDict instead)
enrich_salary(record3)  # ✓ OK
```

## Notes

- **Runtime validation is not optional**: type hints are stripped at runtime; always validate required fields exist and have correct types before processing.
- **TypedDict for dictionaries**: use `TypedDict` instead of Protocol when your source is always a dict; it's stricter and matches JSON/CSV reality.
- **Protocols vs ABCs**: Protocols are structural (any object matching the interface works), ABCs are nominal (must inherit). Protocols are better for third-party code; ABCs are better for internal contracts you control.
- **Test with bad input first**: write tests that pass dicts missing keys, strings where floats are expected, None where required—then write handlers. This catches bugs before production.
- **Revisit: dataclass validation, pydantic models** (stricter, with coercion), and **logging inputs at pipeline boundaries** to know what actually arrived.
