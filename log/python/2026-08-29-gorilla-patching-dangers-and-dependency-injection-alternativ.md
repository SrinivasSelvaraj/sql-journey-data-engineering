---
date: 2026-08-29
phase: python
topic: Gorilla patching dangers and dependency injection alternatives
---

# Gorilla patching dangers and dependency injection alternatives

*Python for data engineering*

## Concept

Gorilla patching (monkey patching) replaces functions, methods, or classes at runtime, typically by assigning new behavior to an object in a module. In data pipelines, this becomes dangerous because patched dependencies create hidden coupling: tests pass in isolation but fail when real dependencies are used, making bugs invisible until production. A common antipattern is patching `requests.get()` globally in test setup, then discovering in production that your API client handles timeouts differently than your mock does.

Dependency injection (DI) inverts this: instead of code reaching into external modules to patch them, you pass dependencies as arguments or inject them via constructors. This makes data flow explicit, testable without side effects, and debuggable—you can see exactly which validator, connection, or transformation a function uses by reading its signature.

For data engineering specifically: ETL jobs are stateful, long-running, and failure-prone. Gorilla patching obscures which database connection, schema validator, or file system a task actually uses. DI lets you swap a real S3 client for a local mock in tests, a dry-run mode in staging, and a batching wrapper in production—all without touching business logic.

## Practice

**Problem:** Your `load_job_postings` function writes to a fact table and should reject rows with NULL `salary_year_avg` or future `job_posted_date`. You want to test rejection logic without hitting the database, and you want to support both Postgres and Snowflake writers without code duplication.

```sql
-- Anti-pattern: gorilla patching in test
-- In production code:
import psycopg2
conn = psycopg2.connect(...)  -- global, patched in test

-- In test:
def test_load():
    with patch('my_module.psycopg2.connect'):
        load_job_postings(rows)  -- hidden dependency
    # Passes, but real Snowflake writer never tested

-- Solution: dependency injection
from dataclasses import dataclass
from abc import ABC, abstractmethod
from typing import List, Protocol

class RowWriter(Protocol):
    def write(self, table: str, rows: List[dict]) -> int: ...
    def validate_schema(self, table: str, row: dict) -> bool: ...

@dataclass
class JobPostingLoader:
    writer: RowWriter
    
    def load(self, rows: List[dict]) -> int:
        validated = [
            row for row in rows 
            if row.get('salary_year_avg') is not None
            and row.get('job_posted_date') <= date.today()
        ]
        return self.writer.write('job_postings_fact', validated)

# Test with mock
class MockWriter:
    def write(self, table, rows):
        return len(rows)
    def validate_schema(self, table, row):
        return True

loader = JobPostingLoader(writer=MockWriter())
assert loader.load([{...}]) == 1  -- no patching, dependency explicit

# Production with Postgres
loader_pg = JobPostingLoader(writer=PostgresWriter(conn))

# Production with Snowflake
loader_sf = JobPostingLoader(writer=SnowflakeWriter(account, user, password))
```

## Notes

- **Hidden state kills debugging**: Gorilla patches live in test setup, not in test code. Six months later, a colleague reads the test and has no idea `psycopg2.connect` was replaced. DI makes it visible in the function signature.
- **Patch scope creeps**: One patched function often leads to patching its dependencies, then theirs. DI lets you stub exactly the boundary you care about (e.g., `RowWriter` interface) without cascading mocks.
- **Connects to: mocking strategies** — DI doesn't eliminate mocking, it just makes it declarative. Use `unittest.mock` for Protocol testing, not for replacing global imports.
- **Revisit: dataclass + Protocol pattern** — this is lighter than full DI frameworks (FastAPI, Pydantic) and sufficient for ETL. Consider Factory Pattern if you need conditional writer selection (Postgres vs. Snowflake) at runtime.
- **Production antipattern**: Don't patch logging, error handlers, or retry logic in tests—these hide real failures. Inject them instead so you test the same error path as production uses.
