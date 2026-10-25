---
date: 2026-10-25
phase: python
topic: Dependency injection for testable pipeline code
---

# Dependency injection for testable pipeline code

*Python for data engineering*

## Concept

Dependency injection means passing objects your code needs *into* functions or classes rather than creating them inside. For data pipelines, this means passing your database connection, logger, config dict, or external API client as parameters instead of hardcoding them. This matters because it lets you swap real dependencies for test doubles (mocks, stubs, fakes) without rewriting your pipeline logic.

Without injection, your extract function calls `psycopg2.connect()` directly, tying it to a real database. Your unit tests either hit that database (slow, flaky, pollutes data) or you can't test at all. With injection, you pass a mock connection and verify your SQL was built correctly, your transformations worked, and your error handling fires when the connection fails—all in milliseconds, offline.

The payoff in data pipelines is huge: you catch bugs in transform logic, null handling, and type coercion before they touch production. You test the *logic* separately from infrastructure.

## Practice

**Problem:** Your `load_job_postings` function writes to `job_postings_fact` and needs to be testable. It should handle null salaries, validate date formats, and log each batch. You want to unit test the transform without a real database.

**Solution:**

```python
from typing import Protocol
from datetime import date
import logging

class JobPostingsWriter(Protocol):
    """Injected dependency for writing records."""
    def write_batch(self, records: list[dict]) -> int:
        """Return count of rows written."""
        ...

def load_job_postings(
    raw_records: list[dict],
    writer: JobPostingsWriter,
    logger: logging.Logger,
) -> int:
    """
    Transform and load job postings.
    
    Args:
        raw_records: Raw data from source
        writer: Injected database writer (real or mock)
        logger: Injected logger
    
    Returns:
        Count of successful writes
    """
    cleaned = []
    for rec in raw_records:
        try:
            job_id = int(rec["job_id"])
            salary = float(rec["salary_year_avg"]) if rec["salary_year_avg"] else None
            posted_date = date.fromisoformat(rec["job_posted_date"])
            
            cleaned.append({
                "job_id": job_id,
                "job_title_short": rec["job_title_short"][:50],
                "salary_year_avg": salary,
                "job_work_from_home": bool(rec.get("job_work_from_home", False)),
                "job_posted_date": posted_date,
                "job_location": rec["job_location"][:100],
            })
        except (ValueError, KeyError) as e:
            logger.warning(f"Skipping record {rec.get('job_id')}: {e}")
    
    count = writer.write_batch(cleaned)
    logger.info(f"Loaded {count} job postings")
    return count

# Unit test using a mock writer
class MockWriter:
    def __init__(self):
        self.records = []
    def write_batch(self, records):
        self.records.extend(records)
        return len(records)

def test_load_job_postings():
    mock_writer = MockWriter()
    mock_logger = logging.getLogger("test")
    
    raw = [
        {
            "job_id": "1",
            "job_title_short": "Data Engineer",
            "salary_year_avg": "120000",
            "job_work_from_home": "true",
            "job_posted_date": "2024-01-15",
            "job_location": "Remote",
        }
    ]
    
    result = load_job_postings(raw, mock_writer, mock_logger)
    assert result == 1
    assert mock_writer.records[0]["salary_year_avg"] == 120000.0
    assert mock_writer.records[0]["job_posted_date"] == date(2024, 1, 15)
```

## Notes

- **Protocol typing** (`from typing import Protocol`) lets you define the shape a dependency must have without coupling to a concrete class—essential for testability in typed Python.
- **Avoid service locators** (global registries or singletons) when possible; they hide dependencies and make tests brittle. Explicit injection makes the contract clear.
- **Three layers to inject:** I/O (database, API, file), configuration (retry counts, batch sizes), and loggers. Keep your transform logic pure and injectable.
- **Adjacent skills:** mocking libraries (`unittest.mock`, `pytest-mock`), fixture management in pytest, and factory patterns for creating test doubles.
- **Revisit when:** You add async I/O (asyncio context managers), orchestrate multiple steps (Airflow tasks need injected run context), or scale to multi-process workers (queues replace direct injection).
