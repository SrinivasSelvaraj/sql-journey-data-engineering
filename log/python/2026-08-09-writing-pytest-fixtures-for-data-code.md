---
date: 2026-08-09
phase: python
topic: Writing pytest fixtures for data code
---

# Writing pytest fixtures for data code

*Python for data engineering*

## Concept

Pytest fixtures are reusable setup objects that eliminate boilerplate in your test suite and make tests more maintainable. In data engineering, fixtures typically provide mock DataFrames, database connections, temporary files, or sample datasets—anything that multiple tests need but shouldn't recreate individually. They matter because data pipelines have heavy dependencies: without fixtures, you either duplicate setup logic across 20 tests or skip testing edge cases entirely. A broken fixture cascade is brutal—one bad mock DataFrame propagates failures across your entire test suite, masking real bugs in transformation logic.

Fixtures shine when testing data validation, schema enforcement, and null-handling. For example, if your pipeline crashes on unexpected column types or missing values, a fixture that reliably generates corrupted or edge-case data lets you verify your code survives it. Without fixtures, you hardcode test data in each test function, making it impossible to test against 50 different bad-input scenarios without 50 duplicate test files.

## Practice

**Problem:** Your ETL job reads `job_postings_fact` and must handle three failure modes: (1) missing salary values, (2) job_posted_date in the future, (3) salary_year_avg as a string instead of numeric. Write a fixture that provides a valid baseline DataFrame, then use it in a parametrized test that verifies your validator catches these errors.

```python
import pytest
import pandas as pd
from datetime import datetime, timedelta

@pytest.fixture
def valid_job_postings():
    """Baseline valid job_postings_fact DataFrame."""
    return pd.DataFrame({
        'job_id': [101, 102, 103],
        'job_title_short': ['Data Engineer', 'Analytics Engineer', 'Data Analyst'],
        'salary_year_avg': [95000.0, 85000.0, 75000.0],
        'job_work_from_home': [True, False, True],
        'job_posted_date': pd.to_datetime(['2024-01-15', '2024-01-20', '2024-01-25']),
        'job_location': ['Remote', 'NYC', 'SF']
    })

@pytest.fixture
def invalid_job_postings(valid_job_postings):
    """Provide corrupted versions for edge-case testing."""
    df = valid_job_postings.copy()
    return {
        'missing_salary': df.copy().loc[0, 'salary_year_avg'] = None,
        'future_date': df.copy().loc[0, 'job_posted_date'] = datetime.now() + timedelta(days=1),
        'salary_as_string': df.copy().assign(salary_year_avg=df['salary_year_avg'].astype(str))
    }

@pytest.mark.parametrize('corrupt_type', ['missing_salary', 'future_date', 'salary_as_string'])
def test_validator_catches_bad_input(valid_job_postings, invalid_job_postings, corrupt_type):
    """Verify validator rejects corrupted data."""
    bad_df = invalid_job_postings[corrupt_type]
    assert not validate_job_postings(bad_df), f"Validator should reject {corrupt_type}"
```

## Notes

- **Scope matters:** Use `@pytest.fixture(scope='module')` for expensive setup (database connections) and `scope='function'` (default) for lightweight data. Mixing them causes tests to interfere with each other.
- **Don't mock what you test:** If you're testing your validator function, give it *real* messy data, not a mock that always passes. The fixture should provide the problem, not hide it.
- **Fixture dependencies form a DAG:** One fixture can depend on another (`invalid_job_postings` depends on `valid_job_postings` above). Keep this chain shallow; deep nesting becomes unreadable.
- **Parametrize + fixtures work together:** Use `@pytest.mark.parametrize` to run the same test against multiple fixture variants without duplicating test code—this is the key to testing 50 bad inputs efficiently.
- **Related:** Learn `pytest.MonkeyPatch` for mocking external calls (APIs, file I/O), `tmpdir` fixtures for temporary test files, and `conftest.py` to share fixtures across multiple test files in a package.
