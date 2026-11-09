---
date: 2026-11-09
phase: python
topic: Coverage.py: measuring and enforcing code coverage targets
---

# Coverage.py: measuring and enforcing code coverage targets

*Python for data engineering*

## Concept

Coverage.py measures what percentage of your codebase is executed during test runs, helping you identify untested code paths—especially critical in data pipelines where silent failures are expensive. It tracks line coverage (did this line run?), branch coverage (did both if/else paths run?), and can enforce minimum thresholds (e.g., "fail CI if coverage drops below 80%"). For data engineering, this matters because pipeline code often handles edge cases—null values, schema mismatches, missing partitions, malformed records—and untested error handlers mean production failures become surprises rather than caught bugs.

Without coverage enforcement, teams drift toward the "it works on my laptop" problem: business logic gets tested, but validation code, retry logic, and exception handlers remain invisible to test suites. A pipeline that handles 99% of clean data perfectly but crashes on 1% of malformed input looks fine in coverage reports if that 1% path is never exercised. Coverage.py forces you to write tests that exercise the boring paths: the `except` block, the `if not df.empty`, the schema validation that seems paranoid until it saves a weekend.

## Practice

**Problem:** Your fact table loader extracts job postings, but you only wrote tests for the happy path. The code contains validation that rejects postings with missing job_id or salary_year_avg <= 0, plus a recovery path that logs and skips bad rows. Your test suite passes, but coverage reports show the validation branches untested.

```python
# pipeline/load_job_postings.py
def validate_and_load(raw_records: list[dict]) -> int:
    """Load job postings, skip invalid rows, return count loaded."""
    loaded = 0
    for record in raw_records:
        try:
            if not record.get('job_id'):
                logger.warning(f"Skipping row: missing job_id")
                continue
            if record.get('salary_year_avg', 0) <= 0:
                logger.warning(f"Skipping job {record['job_id']}: invalid salary")
                continue
            
            # Insert valid record
            insert_fact(
                job_id=record['job_id'],
                job_title_short=record['job_title_short'],
                salary_year_avg=record['salary_year_avg'],
                job_work_from_home=record.get('job_work_from_home', False),
                job_posted_date=record['job_posted_date'],
                job_location=record['job_location']
            )
            loaded += 1
        except Exception as e:
            logger.error(f"Failed to load job {record.get('job_id')}: {e}")
    return loaded


# tests/test_load_job_postings.py
import pytest
from coverage import Coverage

def test_validate_and_load_happy_path(mocker):
    """Test successful load of valid postings."""
    mocker.patch('pipeline.load_job_postings.insert_fact')
    records = [
        {'job_id': 1, 'job_title_short': 'Data Engineer', 'salary_year_avg': 120000, 
         'job_work_from_home': True, 'job_posted_date': '2024-01-15', 'job_location': 'Remote'},
    ]
    assert validate_and_load(records) == 1
    insert_fact.assert_called_once()

def test_validate_and_load_missing_job_id(mocker):
    """Test that records with missing job_id are skipped."""
    mocker.patch('pipeline.load_job_postings.insert_fact')
    records = [
        {'job_title_short': 'Data Engineer', 'salary_year_avg': 120000, 
         'job_work_from_home': True, 'job_posted_date': '2024-01-15', 'job_location': 'Remote'},
    ]
    assert validate_and_load(records) == 0
    insert_fact.assert_not_called()

def test_validate_and_load_invalid_salary(mocker):
    """Test that records with salary <= 0 are skipped."""
    mocker.patch('pipeline.load_job_postings.insert_fact')
    records = [
        {'job_id': 1, 'job_title_short': 'Data Engineer', 'salary_year_avg': -5000, 
         'job_work_from_home': True, 'job_posted_date': '2024-01-15', 'job_location': 'Remote'},
    ]
    assert validate_and_load(records) == 0
    insert_fact.assert_not_called()

def test_validate_and_load_exception_handling(mocker):
    """Test that exceptions during insert are caught and logged."""
    mocker.patch('pipeline.load_job_postings.insert_fact', side_effect=ValueError("DB error"))
    mocker.patch('pipeline.load_job_post
