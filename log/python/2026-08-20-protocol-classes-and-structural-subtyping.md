---
date: 2026-08-20
phase: python
topic: Protocol classes and structural subtyping
---

# Protocol classes and structural subtyping

*Python for data engineering*

## Concept

Protocol classes enable **structural subtyping** in Python—objects satisfy a type contract if they implement the required methods/attributes, regardless of inheritance hierarchy. Unlike nominal typing (where `isinstance()` checks class identity), protocols define shape contracts: "if it has these methods, it's valid here."

In data pipelines, protocols solve a real problem: you want to write functions that accept any reader (CSV file, Parquet, database cursor, API client) without coupling to concrete implementations. A function expecting `Readable` doesn't care *what* object you pass—only that it has `.read()`. Without protocols, you either duplicate code for each type or write overly generic code that loses type information and fails at runtime on edge cases.

Breaks without it: you either use duck typing (no type safety, errors at runtime), type unions that explode in size, or abstract base classes that force inheritance when composition makes more sense. Pipelines then fail silently when a new source doesn't quite match expectations, or you spend cycles debugging "but it has a `.read()` method!" after swapping data sources.

## Practice

**Problem:** Write a type-safe pipeline that loads job postings from any source (CSV, JSON, database), validates that records have `job_id`, `salary_year_avg`, and `job_posted_date`, then writes to the fact table. The loader function must work with any source without modification, and reveal type mismatches at static check time.

```python
from typing import Protocol, Iterator
from datetime import date
from dataclasses import dataclass

class RecordSource(Protocol):
    """Any object that yields dictionaries with job posting data."""
    def records(self) -> Iterator[dict]:
        ...

@dataclass
class JobPosting:
    job_id: int
    job_title_short: str
    salary_year_avg: float
    job_work_from_home: bool
    job_posted_date: date
    job_location: str

def load_and_validate(source: RecordSource) -> Iterator[JobPosting]:
    """Accept any source—CSV reader, database, API—that yields dicts."""
    required_fields = {"job_id", "salary_year_avg", "job_posted_date"}
    for record in source.records():
        missing = required_fields - set(record.keys())
        if missing:
            raise ValueError(f"Row missing fields: {missing}")
        try:
            yield JobPosting(
                job_id=int(record["job_id"]),
                job_title_short=record.get("job_title_short", ""),
                salary_year_avg=float(record.get("salary_year_avg", 0)),
                job_work_from_home=bool(record.get("job_work_from_home", False)),
                job_posted_date=date.fromisoformat(record["job_posted_date"]),
                job_location=record.get("job_location", ""),
            )
        except (ValueError, KeyError) as e:
            raise ValueError(f"Invalid record {record}: {e}")

# Any class with a .records() method works—no inheritance required
class CSVSource:
    def records(self) -> Iterator[dict]:
        import csv
        with open("jobs.csv") as f:
            for row in csv.DictReader(f):
                yield row

class DatabaseSource:
    def __init__(self, cursor):
        self.cursor = cursor
    def records(self) -> Iterator[dict]:
        for row in self.cursor.execute("SELECT * FROM raw_jobs"):
            yield dict(row)

# Both work with the same pipeline
for job in load_and_validate(CSVSource()):
    insert_fact(job)
```

## Notes

- **Common mistake:** confusing Protocols with `ABC` (abstract base class). ABCs require inheritance; protocols don't. Use protocols when you want to accept "anything that looks like X" without enforcing class relationships.
- **Runtime gap:** `isinstance(obj, MyProtocol)` only works if you use `@runtime_checkable`; otherwise protocols are static-check only. Good—it forces you to test structure before runtime.
- **Connects to:** dependency injection (protocols are how you invert dependencies), testing (mock any source that satisfies the protocol shape), and duck typing formalized (gives names to implicit contracts).
- **Revisit:** `typing.TypeVar` and `Generic` for parameterized protocols; `@dataclass` + protocols for lightweight validation; `pydantic` when you need coercion *and* shape validation.
- **Pipeline resilience:** protocols + explicit validation (the `missing` check) catch mismatches early. Silent failures happen when you skip validation; loud errors at load time are feature, not bug.
