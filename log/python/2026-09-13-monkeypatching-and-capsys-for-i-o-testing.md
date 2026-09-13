---
date: 2026-09-13
phase: python
topic: Monkeypatching and capsys for I/O testing
---

# Monkeypatching and capsys for I/O testing

*Python for data engineering*

## Concept

Monkeypatching temporarily replaces functions or objects at runtime, letting you inject test doubles (mocks, stubs) without modifying source code. In data pipelines, you often need to test code that calls external APIs, writes to databases, or reads from file systems—monkeypatching lets you swap these with safe test versions. `capsys` is pytest's built-in fixture that captures stdout and stderr, letting you assert on what your pipeline logged or printed rather than relying on side effects.

Together, they solve a critical testing problem: your ETL task might call `requests.get()` to fetch job postings, or write to a production warehouse. You cannot actually do these things during testing. Monkeypatching replaces `requests.get` with a function that returns fake data; `capsys` verifies your pipeline logged the right warnings when data validation failed. Without these tools, you either skip testing I/O logic entirely (dangerous) or pollute your test environment (expensive and slow).

## Practice

**Problem:** You have a data pipeline that fetches job postings from an API, validates salary_year_avg is not null, and logs warnings for null values. You need to test that validation logic without hitting the real API.

```python
import pytest
from unittest.mock import Mock

def test_job_posting_validation(monkeypatch, capsys):
    """Verify pipeline warns on missing salary and does not insert invalid rows."""
    
    # Monkeypatch: replace the API call with fake data
    fake_response = [
        {"job_id": 1, "job_title_short": "Data Engineer", "salary_year_avg": 120000},
        {"job_id": 2, "job_title_short": "Analyst", "salary_year_avg": None},  # Invalid
        {"job_id": 3, "job_title_short": "Junior DE", "salary_year_avg": 95000},
    ]
    
    def mock_fetch_postings(url: str):
        return fake_response
    
    monkeypatch.setattr("pipeline.fetch_postings", mock_fetch_postings)
    
    # Run the pipeline
    valid_rows = pipeline.validate_and_filter(fake_response)
    
    # capsys: capture logged warnings
    captured = capsys.readouterr()
    
    # Assertions
    assert len(valid_rows) == 2, "Should filter out row with null salary"
    assert "salary_year_avg is null" in captured.out, "Should warn about missing salary"
    assert valid_rows[0]["job_id"] == 1
    assert valid_rows[1]["job_id"] == 3
```

## Notes

- **Monkeypatch scope matters:** use `monkeypatch` (function-scoped) for isolated tests, not `unittest.mock.patch` with decorators if you want pytest style. Always reset after the test—monkeypatch handles this automatically.
- **Mock return types must match:** if your code expects `requests.get()` to return an object with `.json()` method, your mock must do the same. Mismatches fail silently or produce confusing errors.
- **capsys captures print(), not logging:** if your pipeline uses `logging.warning()`, you need `caplog` fixture instead. Mix them when you have both stdout and structured logs.
- **Test file I/O with monkeypatch too:** replace `open()`, `pd.read_csv()`, or database connection objects. The same pattern works—inject test data, verify behavior.
- **Related:** fixtures (dependency injection for tests), parametrize (running same test with multiple inputs), and integration tests (where you *do* hit real databases in controlled environments, usually in CI/CD).
