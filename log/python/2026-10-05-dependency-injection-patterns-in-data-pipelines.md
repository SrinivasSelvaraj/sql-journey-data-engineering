---
date: 2026-10-05
phase: python
topic: Dependency injection patterns in data pipelines
---

# Dependency injection patterns in data pipelines

*Python for data engineering*

## Concept

Dependency injection (DI) in data pipelines means passing external resources—database connections, API clients, config objects, file paths—into functions rather than creating them inside. This separates *what* a function does from *how* it obtains its dependencies, making pipelines testable, portable, and resilient to configuration changes.

Without DI, pipeline code becomes tightly coupled. A function that fetches job postings and writes to a database hardcodes the connection string, making it impossible to test against a dev database or swap in a mock during unit tests. When credentials rotate or schemas change, you edit the function itself rather than swapping configurations. Bad input handling also suffers: if a function creates its own connections, it may retry indefinitely or fail silently instead of propagating errors predictably.

With DI, you pass a database adapter (or mock) into the function signature. Tests inject a fake adapter; production injects the real one. The function stays ignorant of *how* data is persisted, only that it receives something callable. This pattern scales: add logging, retries, or schema validation at the injection point, not inside every pipeline step.

## Practice

**Problem:** You have a function that loads job postings from a CSV, validates salary ranges, and writes to a database. Currently it opens connections and reads files internally, making it impossible to test without touching the real database or filesystem. Adding retry logic or alternative data sources requires modifying the function.

**Solution:**

```python
from typing import Protocol, Iterator
from dataclasses import dataclass
from datetime import date

@dataclass
class JobPosting:
    job_id: int
    job_title_short: str
    salary_year_avg: float
    job_work_from_home: bool
    job_posted_date: date
    job_location: str

class DataSource(Protocol):
    """Contract for reading job postings."""
    def read(self) -> Iterator[dict]:
        ...

class DataSink(Protocol):
    """Contract for writing validated postings."""
    def write(self, posting: JobPosting) -> None:
        ...

def load_and_validate_postings(
    source: DataSource,
    sink: DataSink,
    min_salary: float = 0,
    max_salary: float = 1_000_000
) -> int:
    """Load postings, validate, and persist. Returns count written."""
    count = 0
    for row in source.read():
        try:
            salary = float(row.get("salary_year_avg", 0))
            if not (min_salary <= salary <= max_salary):
                continue
            
            posting = JobPosting(
                job_id=int(row["job_id"]),
                job_title_short=row["job_title_short"],
                salary_year_avg=salary,
                job_work_from_home=row.get("job_work_from_home", False),
                job_posted_date=date.fromisoformat(row["job_posted_date"]),
                job_location=row["job_location"]
            )
            sink.write(posting)
            count += 1
        except (KeyError, ValueError, TypeError) as e:
            # Log and skip bad rows; don't crash the pipeline
            print(f"Skipped invalid row: {e}")
    
    return count

# Test usage with in-memory mock:
class MemorySource:
    def __init__(self, rows: list[dict]):
        self.rows = rows
    def read(self): return iter(self.rows)

class MemoryStore:
    def __init__(self):
        self.postings = []
    def write(self, posting: JobPosting):
        self.postings.append(posting)

# Inject mocks—no database or file I/O needed
source = MemorySource([
    {"job_id": "1", "job_title_short": "Data Engineer", "salary_year_avg": "120000", 
     "job_work_from_home": True, "job_posted_date": "2024-01-15", "job_location": "Remote"},
    {"job_id": "2", "job_title_short": "Analyst", "salary_year_avg": "invalid", ...}  # Bad row handled
])
store = MemoryStore()
count = load_and_validate_postings(source, store, min_salary=80000)
assert len(store.postings) == 1  # Only valid row persisted
```

## Notes

- **Hardcoding vs. protocols:** Using `Protocol` (structural typing) is lighter than forcing implementations to inherit from a base class. The sink only needs a `write()` method—flexibility without ceremony.
- **Error handling at boundaries:** Inject validators and retry handlers at the function call site, not inside. This keeps the core logic clean and testable.
- **Configuration objects:** Group related parameters (min/max salary, batch size, timeouts) into a single `@dataclass` and inject that instead of 10 function arguments.
- **Factory pattern synergy:** DI pairs well with factory functions that
