---
date: 2026-08-28
phase: python
topic: Protocol classes for structural subtyping and mocking
---

# Protocol classes for structural subtyping and mocking

*Python for data engineering*

## Concept

Protocol classes (PEP 544) enable *structural subtyping*—type checking based on what an object can do, not what class it inherits from. In data pipelines, this matters because you often work with database connections, file handles, or API clients that come in many forms (psycopg2, sqlite3, sqlalchemy, mocks). A Protocol lets you define a minimal interface (e.g., `execute(sql) → Cursor`) without forcing all implementations to inherit from a base class. This is especially critical for testing: you can write a mock that quacks like a real database connection, pass it to your extraction function, and verify behavior without spinning up a database. Without Protocols, you either hardcode dependencies (untestable), use duck typing and lose type safety, or create fragile inheritance hierarchies that don't match reality.

## Practice

**Problem:** You have a function that loads `job_postings_fact` from a database using a connection object. You want to write a type-safe unit test that mocks the database without inheriting from the real connection class.

```python
from typing import Protocol, Iterator
from dataclasses import dataclass

class CursorProtocol(Protocol):
    def execute(self, query: str) -> "CursorProtocol": ...
    def fetchall(self) -> list[tuple]: ...

class DBConnectionProtocol(Protocol):
    def cursor(self) -> CursorProtocol: ...
    def close(self) -> None: ...

@dataclass
class JobPosting:
    job_id: int
    job_title_short: str
    salary_year_avg: float
    job_work_from_home: bool
    job_posted_date: str
    job_location: str

def load_job_postings(conn: DBConnectionProtocol) -> list[JobPosting]:
    cursor = conn.cursor()
    cursor.execute("""
        SELECT job_id, job_title_short, salary_year_avg, 
               job_work_from_home, job_posted_date, job_location
        FROM job_postings_fact
        ORDER BY job_posted_date DESC
    """)
    rows = cursor.fetchall()
    cursor.close()
    return [JobPosting(*row) for row in rows]

# Test with a mock that implements the Protocol
class MockCursor:
    def execute(self, query: str) -> "MockCursor":
        return self
    def fetchall(self) -> list[tuple]:
        return [(1, "Data Engineer", 125000.0, True, "2024-01-15", "Remote")]

class MockConnection:
    def cursor(self) -> MockCursor:
        return MockCursor()
    def close(self) -> None:
        pass

# Type checker passes; mock is structurally compatible
postings = load_job_postings(MockConnection())
assert len(postings) == 1
assert postings[0].job_title_short == "Data Engineer"
```

## Notes

- **Structural vs nominal typing:** Protocols say "if it has these methods, it's valid"—no explicit inheritance needed. This makes mocking lightweight and keeps your real code decoupled from test infrastructure.
- **Common mistake:** forgetting `@runtime_checkable` when you need `isinstance()` checks; Protocols are primarily for static type checking, not runtime validation.
- **Connects to:** dependency injection (Protocols define the shape of what you inject), fixture design in pytest, and how real libraries like `sqlalchemy.engine.Connection` are typed.
- **Watch for:** over-specifying Protocols. Only include methods your function actually calls; a bloated Protocol becomes hard to mock and defeats the purpose.
- **Revisit:** `typing_extensions` for backports to older Python, and how mypy/pyright enforce structural subtyping differently from runtime behavior.
