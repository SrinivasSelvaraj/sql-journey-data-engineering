---
date: 2026-11-09
phase: python
topic: Parametrized tests: pytest.mark.parametrize for coverage
---

# Parametrized tests: pytest.mark.parametrize for coverage

*Python for data engineering*

## Concept

Parametrized tests use `pytest.mark.parametrize` to run the same test logic against multiple input sets without code duplication. Instead of writing five nearly-identical test functions, you define one function and decorate it with parameter tuples—each tuple becomes a separate test execution with its own name and report line.

This matters for data pipelines because real data is messy. A salary parser must handle negative values, NULL strings, scientific notation, and empty fields. A date validator must reject '2025-13-45' but accept '2024-12-31'. Testing one happy path isn't enough; parametrized tests let you cover edge cases systematically and maintain them as a readable table, not a wall of similar functions.

Without parametrization, you either skip edge cases (dangerous in production) or write so many test functions that maintenance becomes a burden—refactoring the assertion logic means touching ten nearly-identical stubs.

## Practice

**Problem:** The `job_postings_fact` table accepts salary_year_avg as nullable integer. Your ETL must validate incoming salary values: reject negatives and values over 1,000,000, pass NULL, and convert strings like "150000" or "150_000" to int. Test the parser function thoroughly without repeating assertion logic.

```python
import pytest
from decimal import Decimal

def parse_salary(value) -> int | None:
    """Convert salary input to int. Reject invalid ranges."""
    if value is None or value == '':
        return None
    
    # Remove underscores, convert to int
    cleaned = str(value).replace('_', '').strip()
    try:
        salary = int(cleaned)
    except ValueError:
        raise ValueError(f"Cannot parse salary: {value}")
    
    if salary < 0 or salary > 1_000_000:
        raise ValueError(f"Salary out of valid range: {salary}")
    
    return salary


@pytest.mark.parametrize("input_val,expected", [
    (150000, 150000),
    ("150000", 150000),
    ("150_000", 150000),
    (None, None),
    ("", None),
    (-50000, pytest.raises(ValueError)),
    (1_500_000, pytest.raises(ValueError)),
    ("abc", pytest.raises(ValueError)),
    (Decimal("175000"), 175000),
])
def test_parse_salary(input_val, expected):
    if isinstance(expected, type) and issubclass(expected, Exception):
        with pytest.raises(expected):
            parse_salary(input_val)
    else:
        assert parse_salary(input_val) == expected
```

## Notes

- **ID your parameters:** Use `ids=["valid_int", "string_format", "with_underscore", ...]` in the decorator to make test output readable; otherwise pytest shows `test_parse_salary[150000-150000]` which is cryptic.
- **Use `pytest.raises()` inline:** If you're testing both success and exception cases in the same parametrize, wrap exception assertions with `pytest.raises(ValueError)` or create a separate parametrized test for error paths only.
- **Fixture + parametrize stacking:** You can combine `@pytest.fixture` and `@pytest.mark.parametrize` on the same function—useful when you need both dynamic setup (e.g., a test database) and multiple input scenarios.
- **Generate parameters from data files:** For truly comprehensive coverage, read test cases from CSV or JSON instead of hardcoding tuples; this lets analysts/QA add edge cases without touching Python.
- **Connects to:** Property-based testing with `hypothesis` (generates random inputs automatically), type hints with `Union[int, None]` for clarity, and integration tests that parametrize over multiple target schemas or data sources.
