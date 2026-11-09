---
date: 2026-11-09
phase: python
topic: Test discovery: conftest.py and test organization
---

# Test discovery: conftest.py and test organization

*Python for data engineering*

## Concept

`conftest.py` is a pytest configuration file that pytest automatically discovers and loads before running tests in a directory tree. It centralizes shared fixtures, hooks, and configuration so you don't repeat setup code across dozens of test files. In data pipelines, this is critical because you often need identical database connections, mock data, or temporary schemas across multiple test modules.

Without `conftest.py`, you either duplicate fixture definitions (brittle and hard to maintain) or awkwardly import fixtures from one test file into another (breaks pytest's natural discovery). When your pipeline grows to 20+ test files with overlapping dependencies—like a Postgres connection pool, a staging schema, or sample CSV fixtures—the lack of centralized organization becomes a source of test flakiness and maintenance debt.

Good test organization via `conftest.py` also enables pytest plugins and marks to work across your entire test suite. You can define scope (function, session, module) once and enforce it everywhere, ensuring that expensive resources (database snapshots, cloud credentials) are created and torn down predictably.

## Practice

**Problem:** You have a fact table `job_postings_fact` and you need to write three separate test modules (one for ingestion, one for transformation, one for validation). Each test needs a clean table state with sample rows, but you're duplicating INSERT statements across files.

**Solution:** Use `conftest.py` to define a fixture that seeds the table once per test:

```python
# conftest.py
import pytest
from sqlalchemy import create_engine, text

@pytest.fixture(scope="function")
def job_postings_table(test_db_connection):
    """Seed job_postings_fact with known test data."""
    conn = test_db_connection
    conn.execute(text("""
        DELETE FROM job_postings_fact;
    """))
    conn.execute(text("""
        INSERT INTO job_postings_fact 
        (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
        VALUES 
        (1, 'Data Engineer', 120000, true, '2024-01-15', 'Remote'),
        (2, 'Analytics Engineer', 110000, false, '2024-01-20', 'New York, NY'),
        (3, 'Senior Data Engineer', 150000, true, '2024-01-10', 'San Francisco, CA');
    """))
    conn.commit()
    yield conn
    conn.execute(text("DELETE FROM job_postings_fact;"))
    conn.commit()
```

Then in any test file:
```python
# test_ingestion.py
def test_new_job_posting_inserted(job_postings_table):
    # Table already has 3 rows; add one more
    job_postings_table.execute(text(
        "INSERT INTO job_postings_fact VALUES (4, 'ML Engineer', 130000, true, '2024-01-25', 'Remote')"
    ))
    # Assert...
```

## Notes

- **Scope matters:** `scope="function"` isolates tests but rebuilds fixtures often (slow); `scope="session"` reuses fixtures but risks test pollution. For pipelines, function scope is usually safer despite cost.
- **Conftest location:** pytest searches for `conftest.py` in the test root and parent directories. Use one at `tests/conftest.py` for a shared fixture suite, plus `tests/unit/conftest.py` for unit-only fixtures.
- **Common mistake:** Defining fixtures in `conftest.py` that depend on imports not yet installed in test environments; always pin fixture dependencies in `requirements-dev.txt`.
- **Connects to:** pytest marks (`@pytest.mark.slow`, `@pytest.mark.db`), parametrization for data-driven tests, and CI/CD pipelines that skip expensive fixtures in pull requests.
- **Revisit when:** You add new data sources or need to mock external APIs; update `conftest.py` fixtures rather than spreading mocks across test files.
