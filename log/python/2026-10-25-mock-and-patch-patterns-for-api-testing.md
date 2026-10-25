---
date: 2026-10-25
phase: python
topic: Mock and patch patterns for API testing
---

# Mock and patch patterns for API testing

*Python for data engineering*

## Concept

Mock and patch patterns replace external dependencies (APIs, databases, files) with controlled test doubles during unit testing. In data engineering, you typically mock HTTP clients, database connections, or cloud service SDKs so tests run fast, deterministically, and without side effects. `unittest.mock` (Python standard library) provides `Mock()` objects and the `@patch` decorator to intercept function calls at import time.

Without mocking, pipeline tests become integration tests: they hit real APIs (risking rate limits, inconsistent responses, network failures), depend on external state (a schema that changed), and run slowly. A single bad API response can break 50 tests. Mocking isolates your code's logic—you test that your parsing, transformation, and error handling work correctly given known inputs, independent of whether the API is up.

When you mock, you also force yourself to design for testability: explicit dependency injection (pass the client in, don't create it inside the function), clear contracts (what does this API call return?), and separation of concerns (fetch vs. transform). This makes your pipelines more maintainable and portable.

## Practice

**Problem:** You have a function `fetch_and_load_jobs()` that calls an external job API, parses salary and location, then inserts rows into `job_postings_fact`. You want to test the parsing and insertion logic without hitting the real API or database.

```python
from unittest.mock import Mock, patch, call
import pytest

def fetch_and_load_jobs(api_client, db_connection):
    """Fetch jobs from API, parse, and insert into database."""
    response = api_client.get_jobs(limit=100)
    records = [
        {
            "job_id": job["id"],
            "job_title_short": job["title"][:50],
            "salary_year_avg": job.get("salary_max"),
            "job_work_from_home": job.get("remote", False),
            "job_posted_date": job["posted_date"],
            "job_location": job.get("location", "Unknown"),
        }
        for job in response["jobs"]
    ]
    db_connection.insert_batch("job_postings_fact", records)
    return len(records)

# Test with mocked API and database
def test_fetch_and_load_jobs():
    mock_api = Mock()
    mock_db = Mock()
    
    # Define what the mock API returns
    mock_api.get_jobs.return_value = {
        "jobs": [
            {
                "id": 1,
                "title": "Senior Data Engineer",
                "salary_max": 180000,
                "remote": True,
                "posted_date": "2024-01-15",
                "location": "Remote",
            },
            {
                "id": 2,
                "title": "Analytics Engineer",
                "salary_max": 120000,
                "remote": False,
                "posted_date": "2024-01-14",
                "location": "NYC",
            },
        ]
    }
    
    # Call the function
    count = fetch_and_load_jobs(mock_api, mock_db)
    
    # Verify behavior
    assert count == 2
    mock_api.get_jobs.assert_called_once_with(limit=100)
    
    # Check what was inserted
    inserted = mock_db.insert_batch.call_args[0][1]
    assert inserted[0]["job_title_short"] == "Senior Data Engineer"
    assert inserted[0]["job_work_from_home"] is True
    assert inserted[1]["job_location"] == "NYC"
```

## Notes

- **Common mistake:** Over-mocking. Mock only external I/O (APIs, databases, file systems). Don't mock your own business logic or utility functions—test those for real so you catch bugs.
- **Patch location matters:** `@patch("module.function")` patches where the object is *used*, not where it's defined. If `fetch_and_load_jobs` imports `requests`, patch `your_module.requests`, not `requests.requests`.
- **Side effects and exceptions:** Use `side_effect` to raise exceptions (`mock_api.get_jobs.side_effect = ConnectionError()`) to test error handling paths without relying on flaky networks.
- **Fixture pollution:** Reset mocks between tests or use `@patch` as a decorator (it auto-cleans). Reusing mock state across tests causes mysterious failures.
- **Adjacent topic:** *Fixtures* (pytest) and *parametrization* make mock setup reusable; *spy patterns* (wrapping real objects) bridge mocking and integration testing when you need both.
