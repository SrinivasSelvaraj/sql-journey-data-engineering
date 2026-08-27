---
date: 2026-08-27
phase: python
topic: Exception hierarchy: custom exceptions vs built-in types
---

# Exception hierarchy: custom exceptions vs built-in types

*Python for data engineering*

## Concept

Python's built-in exceptions (ValueError, TypeError, KeyError) are generic—they don't tell you *why* something failed in your pipeline. When parsing malformed CSV rows or validating salary data, a bare `ValueError` could mean a missing column, bad type cast, or out-of-range value. Custom exceptions let you catch and handle domain-specific failures precisely, making pipelines testable and debuggable.

The exception hierarchy matters because it lets you write recovery logic at the right level. A `SalaryOutOfRangeError` inheriting from `ValidationError` lets you retry ingestion differently than a `DataSourceConnectionError` inheriting from `IOError`. Without it, you either catch everything (hiding bugs) or catch nothing (letting bad data through). In ETL, this is the difference between a pipeline that fails loudly at the right place and one that silently corrupts your fact table.

## Practice

**Problem:** You're loading job postings into `job_postings_fact`. The source CSV sometimes has missing salary data, sometimes has salary values that exceed your schema's int range, and sometimes has invalid dates. You need to validate, log what went wrong, and decide per-row whether to skip, retry, or fail the entire load.

```python
class DataValidationError(Exception):
    """Base class for validation failures in ETL"""
    pass

class MissingSalaryError(DataValidationError):
    """Raised when salary_year_avg is NULL or absent"""
    pass

class SalaryOutOfRangeError(DataValidationError):
    """Raised when salary exceeds schema constraints (e.g., > 2_147_483_647)"""
    pass

class InvalidDateError(DataValidationError):
    """Raised when job_posted_date cannot be parsed"""
    pass

def validate_and_load_row(row: dict) -> dict:
    """Validate a job posting row; raise specific exceptions on failure."""
    try:
        salary = int(row.get('salary_year_avg'))
        if salary < 0 or salary > 2_147_483_647:
            raise SalaryOutOfRangeError(
                f"Salary {salary} out of range for job_id {row['job_id']}"
            )
    except ValueError:
        raise MissingSalaryError(
            f"Missing or non-numeric salary for job_id {row['job_id']}"
        )
    
    try:
        pd.to_datetime(row['job_posted_date'])
    except Exception:
        raise InvalidDateError(
            f"Invalid date '{row['job_posted_date']}' for job_id {row['job_id']}"
        )
    
    return row

def load_job_postings(csv_path: str, df: pd.DataFrame) -> int:
    """Load rows into job_postings_fact; skip invalid rows, log errors."""
    loaded = 0
    for idx, row in df.iterrows():
        try:
            validate_and_load_row(row.to_dict())
            # INSERT INTO job_postings_fact ...
            loaded += 1
        except MissingSalaryError as e:
            logger.warning(f"Row {idx}: {e} — skipping")
        except InvalidDateError as e:
            logger.warning(f"Row {idx}: {e} — skipping")
        except SalaryOutOfRangeError as e:
            logger.error(f"Row {idx}: {e} — requires review")
            raise  # Fail the pipeline; this is a data quality issue
    
    return loaded
```

## Notes

- **Catch specific, raise specific:** Never `except Exception:`. Catch `MissingSalaryError` or `DataValidationError` (parent), log context, and decide to skip or retry. Generic catches hide bugs in unrelated code.
- **Inheritance structure matters:** Build a hierarchy (base `DataValidationError` → `SalaryOutOfRangeError`, `MissingSalaryError`, etc.) so calling code can handle classes of errors together or individually.
- **Add context in the message:** Include row IDs, values, and schema constraints in exception messages. You'll debug logs, not stack traces, in production.
- **Connects to typing & testability:** Use `@pytest.mark.parametrize` to test each exception path; type hints (`-> dict`) make it clear what succeeds. Custom exceptions become part of your API contract.
- **Revisit: logging levels and alerting.** `warning` for skipped rows (recoverable), `error` for pipeline-halting issues. Tie alerts to exception types, not log messages.
