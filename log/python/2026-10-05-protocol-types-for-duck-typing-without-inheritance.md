---
date: 2026-10-05
phase: python
topic: Protocol types for duck-typing without inheritance
---

# Protocol types for duck-typing without inheritance

*Python for data engineering*

## Concept

Protocol types (from `typing.Protocol`) define structural interfaces that any class can satisfy without explicit inheritance. Instead of checking "is this a Dog?" the type system asks "does this quack like a duck?"—does it have the methods I need? In data pipelines, this matters because you often work with external APIs, database drivers, and third-party libraries that won't inherit from your base classes. Without protocols, you either force rigid inheritance chains or lose type safety when swapping implementations (e.g., switching from PostgreSQL to Snowflake connectors).

Protocols are especially powerful in ETL code: a source reader might be a CSV parser, an API client, or a database query—all structurally different—but if they all implement `read() → Iterator[dict]`, one protocol captures them all. Without this, you either write brittle duck-typing (no type hints) or overfit your pipeline to one vendor. Breaking down without protocols means lost IDE autocomplete, runtime errors deep in processing, and refactoring nightmares when you need to swap data sources mid-project.

## Practice

**Problem:** You're building a data pipeline that reads job postings from multiple sources (CSV files, REST APIs, Parquet exports). Each source has a different interface, but all produce records matching the `job_postings_fact` schema. You need type-safe, swappable readers without forcing them to inherit a base class.

```python
from typing import Protocol, Iterator
from datetime import date

class JobPostingReader(Protocol):
    """Any source that yields job posting dicts matching the schema."""
    def read(self) -> Iterator[dict[str, int | str | bool | date]]:
        ...

class CSVJobReader:
    def __init__(self, filepath: str):
        self.filepath = filepath
    
    def read(self) -> Iterator[dict[str, int | str | bool | date]]:
        import csv
        with open(self.filepath) as f:
            for row in csv.DictReader(f):
                yield {
                    "job_id": int(row["job_id"]),
                    "job_title_short": row["job_title"],
                    "salary_year_avg": int(row["salary"]) if row["salary"] else 0,
                    "job_work_from_home": row["remote"].lower() == "true",
                    "job_posted_date": date.fromisoformat(row["posted_date"]),
                    "job_location": row["location"],
                }

class APIJobReader:
    def __init__(self, endpoint: str):
        self.endpoint = endpoint
    
    def read(self) -> Iterator[dict[str, int | str | bool | date]]:
        # Different implementation, same interface
        import requests
        for item in requests.get(self.endpoint).json():
            yield {
                "job_id": item["id"],
                "job_title_short": item["title"],
                "salary_year_avg": item.get("salary", 0),
                "job_work_from_home": item.get("remote", False),
                "job_posted_date": date.fromisoformat(item["timestamp"].split("T")[0]),
                "job_location": item["location"],
            }

def ingest_jobs(reader: JobPostingReader, batch_size: int = 1000) -> None:
    """Type-safe pipeline: accepts any reader satisfying the protocol."""
    batch = []
    for record in reader.read():
        batch.append(record)
        if len(batch) >= batch_size:
            print(f"Inserting {len(batch)} records...")
            batch.clear()
    if batch:
        print(f"Inserting final {len(batch)} records...")

# Both readers work interchangeably
csv_reader = CSVJobReader("jobs.csv")
api_reader = APIJobReader("https://api.example.com/jobs")
ingest_jobs(csv_reader)
ingest_jobs(api_reader)
```

## Notes

- **Structural vs. nominal typing:** Protocols are *structural*—Python checks if methods exist, not class names. This is foreign to Java/C# developers; don't expect `isinstance()` to work by default (use `@runtime_checkable` if you must, but it's a code smell).
- **Common mistake:** Defining a protocol with methods but forgetting to annotate the actual implementations with matching signatures. Type checkers won't catch mismatches if return types differ subtly (e.g., `dict` vs. `dict[str, Any]`).
- **Connects to:** Type narrowing with `isinstance()` (when you *do* need runtime checks), generics (protocols with `TypeVar` for flexible payloads), and `functools.wraps` for decorator testing.
- **Adjacent pattern:** Dependency injection—protocols pair well with factory functions or service locators to swap implementations at test/deploy time without touching pipeline logic.
- **Revisit when:** adding new data sources, writing fixtures for unit tests, or debugging "but it worked with PostgreSQL" errors that surface only with Snowflake
