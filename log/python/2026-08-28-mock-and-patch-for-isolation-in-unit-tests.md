---
date: 2026-08-28
phase: python
topic: Mock and patch for isolation in unit tests
---

# Mock and patch for isolation in unit tests

*Python for data engineering*

## Concept

Mock and patch replace external dependencies (APIs, databases, file systems) with controlled substitutes during unit tests, so your code logic is tested in isolation without side effects. When testing a data pipeline that fetches job postings from an API and loads them into a warehouse, you don't want the test to actually call the API or write to production tables—you want to verify the transformation and error handling logic works correctly.

Without mocking, tests become brittle and slow: they fail when external services are down, create unwanted data in staging environments, and couple your test suite to infrastructure. With `unittest.mock.patch`, you intercept function calls and replace them with stubs or spies that return predictable values, raise controlled exceptions, and let you verify how your code calls them.

This matters most in data pipelines because they sit at the boundary between systems. Your extraction layer talks to APIs; your loading layer writes to databases. If you test without isolation, you're testing the third-party code, not your own.

## Practice

**Problem:** You have a function that fetches job postings from an API, filters by work-from-home status, and returns a list of dictionaries. You need to test that it correctly handles API timeouts without actually calling the live API.

```python
# solution: use patch to mock the requests library
from unittest.mock import patch, MagicMock
import requests

def fetch_job_postings(api_url: str) -> list[dict]:
    response = requests.get(api_url, timeout=5)
    response.raise_for_status()
    return response.json().get('jobs', [])

def test_fetch_job_postings_timeout():
    """Verify that timeout exceptions are handled gracefully."""
    with patch('requests.get') as mock_get:
        mock_get.side_effect = requests.Timeout("Connection timed out")
        
        with pytest.raises(requests.Timeout):
            fetch_job_postings("https://api.example.com/jobs")
        
        # Verify we tried to call the API exactly once
        mock_get.assert_called_once_with("https://api.example.com/jobs", timeout=5)

def test_fetch_job_postings_success():
    """Verify parsing of successful API response."""
    mock_response = MagicMock()
    mock_response.json.return_value = {
        'jobs': [
            {'job_id': 1, 'title': 'Data Engineer', 'work_from_home': True},
            {'job_id': 2, 'title': 'Analyst', 'work_from_home': False}
        ]
    }
    
    with patch('requests.get', return_value=mock_response):
        result = fetch_job_postings("https://api.example.com/jobs")
        assert len(result) == 2
        assert result[0]['job_id'] == 1
```

## Notes

- **Patch location matters:** patch the import where it's *used*, not where it's defined. If your module does `from requests import get`, patch `'your_module.get'`, not `'requests.get'`.
- **Avoid over-mocking:** mock external boundaries (APIs, DB drivers, file I/O), not internal functions. Over-mocking makes tests brittle and defeats the purpose of testing logic.
- **Use `MagicMock` for complex returns:** when the mocked function returns an object with methods or attributes (like a response object), use `MagicMock` and set `.return_value` or chain attributes with dot notation.
- **Connect to testability:** writing code that's easy to mock requires dependency injection and clear separation between I/O and logic. Hard-to-test code often signals tight coupling.
- **Revisit: fixtures and factories** for reusable mock data, and **pytest-mock** plugin as a cleaner alternative to manual patching in larger test suites.
