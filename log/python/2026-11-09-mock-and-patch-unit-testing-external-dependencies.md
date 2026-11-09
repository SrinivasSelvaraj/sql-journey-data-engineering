---
date: 2026-11-09
phase: python
topic: Mock and patch: unit testing external dependencies
---

# Mock and patch: unit testing external dependencies

*Python for data engineering*

## Concept

Mock and patch allow you to replace external dependencies (APIs, databases, file systems, third-party libraries) with controlled test doubles during unit testing. Instead of hitting a real Postgres database or making actual HTTP calls to a job board API, you inject a fake object that returns predictable responses. This isolates your code logic from infrastructure, making tests fast, deterministic, and safe to run in CI/CD without side effects.

Without mocking, tests become integration tests: they fail when the database is down, when rate limits are hit, or when external services change. Your pipeline code that transforms job postings becomes untestable because it's tightly coupled to a live data source. Mocking breaks that coupling—you test the *transformation logic*, not the retrieval mechanism.

The `unittest.mock` library (built-in Python) provides `Mock`, `patch`, and `MagicMock` objects. `patch` replaces a function/class at the point where it's imported; `Mock` creates spy objects that track calls. This is essential for data pipelines: test your ETL business logic in isolation, then test connectors separately.

## Practice

**Problem:** Your pipeline has a function that filters and enriches job postings. It calls `fetch_postings_from_db()` to get raw data, then applies business rules (remove postings older than 30 days, flag remote work). You need to unit test the filtering logic without querying the actual database.

```python
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta

def filter_and_enrich_postings(job_id_min=1):
    """Load, filter, and return job postings."""
    postings = fetch_postings_from_db()
    cutoff_date = datetime.now() - timedelta(days=30)
    filtered = [
        {**p, 'is_recent': p['job_posted_date'] >= cutoff_date}
        for p in postings
        if p['job_id'] >= job_id_min
    ]
    return filtered

def fetch_postings_from_db():
    """External dependency: real database call."""
    # Connection logic, query, etc.
    pass

# Unit test with mock
@patch('your_module.fetch_postings_from_db')
def test_filter_and_enrich_postings(mock_db):
    # Arrange: mock returns controlled test data
    mock_db.return_value = [
        {
            'job_id': 1,
            'job_title_short': 'Data Engineer',
            'salary_year_avg': 120000,
            'job_work_from_home': True,
            'job_posted_date': datetime.now() - timedelta(days=5),
            'job_location': 'Remote'
        },
        {
            'job_id': 2,
            'job_title_short': 'Analyst',
            'salary_year_avg': 85000,
            'job_work_from_home': False,
            'job_posted_date': datetime.now() - timedelta(days=40),
            'job_location': 'NYC'
        }
    ]
    
    # Act
    result = filter_and_enrich_postings()
    
    # Assert
    assert len(result) == 1
    assert result[0]['job_id'] == 1
    assert result[0]['is_recent'] is True
    mock_db.assert_called_once()
```

## Notes

- **Patch location matters:** patch where the function is *used*, not where it's defined. If your module does `from db_module import fetch_postings_from_db`, patch `'your_module.fetch_postings_from_db'`, not `'db_module.fetch_postings_from_db'`.
- **Avoid over-mocking:** mock external I/O and side effects only. Don't mock your own business logic—test it directly. Over-mocking creates tests that pass but don't catch real bugs.
- **Side effect vs. return_value:** use `mock.return_value` for simple returns; use `mock.side_effect` for exceptions, sequences, or callable logic. E.g., `mock_db.side_effect = ConnectionError()` to test error handling.
- **Spy on calls:** use `assert_called_once()`, `assert_called_with()`, `call_count`, and `call_args` to verify your code actually invoked the dependency correctly—useful for ensuring pagination or retry logic works.
- **Related:** fixture factories (pytest), parameterized tests for multiple scenarios, and integration test suites that run against real infrastructure in staging environments.
