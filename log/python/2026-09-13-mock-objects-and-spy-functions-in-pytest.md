---
date: 2026-09-13
phase: python
topic: Mock objects and spy functions in pytest
---

# Mock objects and spy functions in pytest

*Python for data engineering*

## Concept

Mock objects and spy functions let you isolate the code under test by replacing external dependencies—databases, APIs, file systems—with controlled substitutes. In data pipelines, this is critical: you can't afford to hit a real data warehouse on every test run, and you need to verify that your transformation logic calls the right functions with the right arguments, even when those functions fail. Mocks let you test error handling paths (malformed JSON, null salary fields, missing dates) without setting up expensive fixtures.

A spy function is a mock that also records how it was called—argument values, call count, exceptions raised. Without mocks and spies, your pipeline tests become brittle integration tests: they depend on external state, run slowly, and fail for reasons unrelated to your code (network timeouts, database locks). With them, tests run in milliseconds, are deterministic, and catch real bugs in your transformation logic.

## Practice

**Problem:** Your pipeline function `load_job_postings()` fetches raw job data from an API, validates it, and calls `insert_fact_table()` to write to a data warehouse. You need to:
1. Verify the function handles a null salary gracefully (skips the row)
2. Confirm `insert_fact_table()` was called with exactly 2 rows when given 3 raw records (one with null salary)
3. Ensure that if the API times out, the error is logged and re-raised

```python
from unittest.mock import Mock, patch, call
import pytest

def test_load_job_postings_skips_null_salary(monkeypatch):
    # Mock the external API
    mock_api = Mock(return_value=[
        {"job_id": 1, "title": "Engineer", "salary": 100000, "remote": True, "posted": "2024-01-15", "location": "NYC"},
        {"job_id": 2, "title": "Analyst", "salary": None, "remote": False, "posted": "2024-01-16", "location": "LA"},
        {"job_id": 3, "title": "Manager", "salary": 120000, "remote": True, "posted": "2024-01-17", "location": "SF"},
    ])
    
    # Spy on the warehouse insert function
    mock_insert = Mock()
    
    # Inject mocks
    monkeypatch.setattr("my_pipeline.fetch_api", mock_api)
    monkeypatch.setattr("my_pipeline.insert_fact_table", mock_insert)
    
    # Run the pipeline
    from my_pipeline import load_job_postings
    load_job_postings()
    
    # Assert: insert called exactly once with 2 valid rows
    assert mock_insert.call_count == 1
    inserted_rows = mock_insert.call_args[0][0]
    assert len(inserted_rows) == 2
    assert inserted_rows[0]["job_id"] == 1
    assert inserted_rows[1]["job_id"] == 3
```

## Notes

- **Mock return values matter:** Use `return_value` for normal responses, `side_effect` to raise exceptions. Test both success and failure paths separately.
- **Avoid over-mocking:** Mock external boundaries (APIs, databases, file I/O) but test your transformation logic with real Python objects when possible.
- **`call_args` and `call_args_list`:** Inspect exactly what arguments were passed; use `call()` objects to assert sequences of calls—crucial for verifying ETL ordering.
- **Monkeypatch vs. `patch()`:** Monkeypatch (pytest fixture) is cleaner for single tests; `patch()` as a context manager or decorator scales to parameterized test suites.
- **Adjacent skill:** Learn assertion helpers like `pytest.approx()` for floating-point salary comparisons, and `freezegun` for mocking `datetime.now()` so your `job_posted_date` tests don't fail at midnight.
