---
date: 2026-09-13
phase: python
topic: Setup and teardown fixtures with scope isolation
---

# Setup and teardown fixtures with scope isolation

*Python for data engineering*

## Concept

Fixtures with scope isolation control the lifecycle and visibility of test resources—databases, temporary files, mock objects—ensuring each test gets a clean state without interference. In data pipelines, this means setting up test data once per module or session, sharing it safely across tests, and tearing down only when needed. Without proper scope isolation, tests leak state (one test's insert pollutes another's assertions), fixtures run redundantly (wasting seconds on repeated ETL setup), and teardown happens at the wrong time (leaving orphaned tables or temp files).

The key scopes are `function` (default, freshest but slowest), `module` (balance), `session` (shared across all tests, fastest but requires isolation discipline), and `class` (for grouped test suites). A data pipeline test typically uses `session`-scoped fixtures for expensive reads (loading reference data, spawning a test database) and `function`-scoped fixtures for mutable state (inserting test job postings, resetting sequences).

## Practice

**Problem:** You're testing a pipeline that transforms raw job posting CSVs into a fact table. Each test needs a fresh copy of the dimension data (job titles, locations) to join against, but the raw CSV is 50MB and takes 3 seconds to load. Loading it fresh for every test (20 tests) wastes 60 seconds. You also need to insert different job posting scenarios per test without cross-contamination.

```python
import pytest
from sqlalchemy import create_engine, text

@pytest.fixture(scope="session")
def test_db():
    """Session-scoped: spawn test DB once, reuse for all tests."""
    engine = create_engine("sqlite:///:memory:")
    with engine.begin() as conn:
        conn.execute(text("""
            CREATE TABLE job_postings_fact (
                job_id INT PRIMARY KEY,
                job_title_short TEXT,
                salary_year_avg DECIMAL,
                job_work_from_home BOOLEAN,
                job_posted_date DATE,
                job_location TEXT
            )
        """))
        # Load expensive reference data once
        conn.execute(text("""
            INSERT INTO job_postings_fact VALUES
            (101, 'Data Engineer', 120000, 1, '2024-01-15', 'Remote'),
            (102, 'Analyst', 95000, 0, '2024-01-16', 'New York')
        """))
    yield engine
    engine.dispose()

@pytest.fixture(scope="function")
def clean_postings(test_db):
    """Function-scoped: truncate mutable data before each test."""
    with test_db.begin() as conn:
        conn.execute(text("DELETE FROM job_postings_fact WHERE job_id > 1000"))
    yield test_db
    # Implicit cleanup: truncate happens again on next test's setup

def test_remote_jobs_filter(clean_postings):
    """Insert test data, run assertion, auto-cleanup on exit."""
    with clean_postings.begin() as conn:
        conn.execute(text("""
            INSERT INTO job_postings_fact 
            VALUES (1001, 'ML Eng', 150000, 1, '2024-02-01', 'Remote')
        """))
        result = conn.execute(text(
            "SELECT COUNT(*) FROM job_postings_fact WHERE job_work_from_home = 1"
        )).scalar()
    assert result >= 1  # Reference data + inserted row

def test_salary_aggregation(clean_postings):
    """Separate test: no pollution from test_remote_jobs_filter."""
    with clean_postings.begin() as conn:
        conn.execute(text("""
            INSERT INTO job_postings_fact 
            VALUES (1002, 'Data Scientist', 140000, 0, '2024-02-02', 'Boston')
        """))
        avg_salary = conn.execute(text(
            "SELECT AVG(salary_year_avg) FROM job_postings_fact"
        )).scalar()
    assert avg_salary > 100000
```

## Notes

- **Scope mismatch kills tests:** Using `function` scope for expensive resources (full warehouse bootstrap) makes CI timeout; using `session` scope for mutable test inserts causes false failures when order changes.
- **Autouse fixtures run silently:** Mark fixtures with `@pytest.fixture(autouse=True)` to run setup/teardown without being passed as arguments—useful for resetting sequences or clearing caches before each test.
- **Fixture parametrization:** Combine scopes with `@pytest.mark.parametrize` on fixtures themselves to generate multiple versions (e.g., test against PostgreSQL and SQLite simultaneously).
- **Teardown order matters in pipelines:** If a fixture creates a temp schema and another populates it, ensure population fixtures depend (request) the schema fixture so teardown reverses the dependency chain.
- **Connects to:** mocking external APIs (use `session` scope for mock server, `function` for request stubs), integration vs. unit testing
