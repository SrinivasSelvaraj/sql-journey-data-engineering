---
date: 2026-08-27
phase: python
topic: Dependency injection patterns for testable data code
---

# Dependency injection patterns for testable data code

*Python for data engineering*

## Concept

Dependency injection (DI) is a pattern where a function or class receives its dependencies (database connections, API clients, file handles, configuration) as parameters rather than creating them internally. In data pipelines, this decouples your transformation logic from infrastructure details, making unit tests fast and deterministic.

Without DI, your extract–transform–load functions are tightly coupled to specific databases, APIs, or file systems. Testing requires real connections, real data, and real side effects. When a dependency fails or changes, you rewrite the function. With DI, you inject a mock database adapter or test fixture, verify logic in isolation, and swap implementations for different environments without touching your core logic.

This matters most when your pipeline spans multiple stages (raw → bronze → silver → gold) and needs to handle schema changes, API rate limits, or credential rotation. Bad input and missing fields crash the whole pipeline; injected validators and error handlers let you fail gracefully at each layer.

## Practice

**Problem:** You have a `load_job_postings()` function that reads job_postings_fact from a production database and computes average salary by location. If the database is down, the job fails hard. You want to test salary logic without hitting the real database.

**Solution using dependency injection:**

```python
from typing import Protocol
from dataclasses import dataclass
import pandas as pd

class JobPostingsRepository(Protocol):
    """Contract: any object with this method can be injected."""
    def fetch_all(self) -> pd.DataFrame:
        ...

def compute_avg_salary_by_location(
    repo: JobPostingsRepository,
    min_salary: float = 0.0
) -> pd.DataFrame:
    """Pure logic: depends only on the interface, not implementation."""
    df = repo.fetch_all()
    df = df[df['salary_year_avg'] >= min_salary]
    return df.groupby('job_location').agg({
        'salary_year_avg': ['mean', 'count']
    }).reset_index()

# Production implementation
class PostgresJobRepository:
    def __init__(self, connection_string: str):
        self.conn_str = connection_string
    
    def fetch_all(self) -> pd.DataFrame:
        import psycopg2
        conn = psycopg2.connect(self.conn_str)
        return pd.read_sql(
            "SELECT * FROM job_postings_fact",
            conn
        )

# Test implementation
class MockJobRepository:
    def fetch_all(self) -> pd.DataFrame:
        return pd.DataFrame({
            'job_id': [1, 2, 3],
            'job_title_short': ['DE', 'DA', 'DE'],
            'salary_year_avg': [120000, 95000, 130000],
            'job_work_from_home': [True, False, True],
            'job_posted_date': ['2024-01-01'] * 3,
            'job_location': ['Remote', 'NYC', 'Remote']
        })

# Test: no database needed, runs in milliseconds
def test_compute_avg_salary():
    repo = MockJobRepository()
    result = compute_avg_salary_by_location(repo, min_salary=100000)
    assert len(result) == 2  # Remote and NYC
    assert result[result['job_location'] == 'Remote']['salary_year_avg']['mean'].values[0] == 125000
```

## Notes

- **Mistake:** Hardcoding `psycopg2.connect()` inside the transformation function. Use `__init__` parameters or context managers to inject connections before calling logic.
- **Mistake:** Over-mocking. Mock only external I/O (databases, APIs, files); test real business logic against mock data.
- **Adjacent topic:** Use `Protocol` (or ABC) to define contracts instead of concrete types—this lets you swap implementations without changing signatures.
- **Worth revisiting:** Combine with type hints and `mypy` to catch injection errors at lint time; pair with factory functions or dependency containers (e.g., `injector`, `pydantic-settings`) for larger pipelines.
- **Testing strategy:** Test compute functions with mock repos, then separately test repo implementations with test databases or fixtures.
