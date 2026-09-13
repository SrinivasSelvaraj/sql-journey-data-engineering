---
date: 2026-09-13
phase: python
topic: Parametrized tests and hypothesis property-based testing
---

# Parametrized tests and hypothesis property-based testing

*Python for data engineering*

## Concept

Parametrized tests let you run the same test logic across multiple input sets without writing repetitive test functions. In pytest, `@pytest.mark.parametrize` accepts a list of arguments and runs your test once per tuple, catching edge cases that a single happy-path test misses. Hypothesis property-based testing goes further: it generates hundreds of random valid inputs according to rules you define, then shrinks failures to minimal reproducible examples—invaluable for pipeline code that must handle malformed dates, null salary fields, or unexpected location formats.

These matter because production data is messy. A data pipeline that works on 100 clean rows fails catastrophically on row 50,001 when someone uploads a CSV with a typo in the date column. Parametrized tests catch known problem cases (empty strings, negative salaries, future dates). Hypothesis finds the cases you didn't think to test, generating edge cases like leap-year dates or Unicode characters in job titles that break string parsing.

Without them, your pipeline only validates against the data you happened to see, not the data that will actually arrive. You deploy with confidence, then get paged at 3am because a null salary crashed your aggregation.

## Practice

**Problem:** Your ETL loads `job_postings_fact` and must reject rows where `salary_year_avg` is negative, `job_posted_date` is in the future, or `job_location` is empty. You need to test these validations without manually writing a dozen test functions.

```python
import pytest
from datetime import datetime, timedelta
from hypothesis import given, strategies as st

# Parametrized: test known bad cases
@pytest.mark.parametrize("salary,is_valid", [
    (50000, True),
    (-1, False),
    (0, False),
    (999999, True),
])
def test_salary_validation(salary, is_valid):
    assert validate_salary(salary) == is_valid

@pytest.mark.parametrize("location,is_valid", [
    ("New York, NY", True),
    ("", False),
    ("Remote", True),
    (None, False),
])
def test_location_validation(location, is_valid):
    assert validate_location(location) == is_valid

# Property-based: generate random valid data, ensure it never breaks
@given(
    salary=st.integers(min_value=1, max_value=1_000_000),
    location=st.text(min_size=1),
    posted_date=st.dates(
        min_value=datetime(2020, 1, 1).date(),
        max_value=datetime.now().date()
    )
)
def test_pipeline_never_crashes_on_valid_input(salary, location, posted_date):
    row = {
        "job_id": "123",
        "job_title_short": "Data Engineer",
        "salary_year_avg": salary,
        "job_location": location,
        "job_posted_date": posted_date,
        "job_work_from_home": False
    }
    # Should never raise, even on random Unicode or edge-case numbers
    result = transform_row(row)
    assert result is not None
```

## Notes

- **Parametrize IDs:** Use `ids=` parameter in `@pytest.mark.parametrize` to label test cases (e.g., `ids=["valid_salary", "negative_salary"]`); raw output is unreadable with 20+ cases.
- **Hypothesis + nullable columns:** Use `st.one_of(st.none(), st.text())` to test both NULL and non-NULL paths; many pipeline bugs hide in unhandled nulls.
- **Shrinking is the superpower:** When Hypothesis finds a failure, it automatically reduces to simplest input (e.g., empty string instead of 10,000-char Unicode blob), making debugging instant.
- **Avoid over-mocking with Hypothesis:** Let it hit real transformation logic, not stubs; the point is to find what actually breaks.
- **Connects to:** schema validation (pydantic), type hints (mypy), and integration tests; parametrized tests live at the unit level, but Hypothesis-style thinking scales to full pipeline data contracts.
