---
date: 2026-09-12
phase: python
topic: Custom exception hierarchies for pipeline error handling
---

# Custom exception hierarchies for pipeline error handling

*Python for data engineering*

## Concept

A custom exception hierarchy organizes pipeline errors into meaningful categories, making failures debuggable and recoverable. Instead of catching generic `Exception`, you define domain-specific exceptions (e.g., `DataValidationError`, `SourceConnectionError`, `SchemaEvolutionError`) that signal *what went wrong* and *where*. This matters because data pipelines fail frequently—bad input, network flakes, schema drift—and you need to distinguish between recoverable errors (retry) and fatal ones (alert). Without hierarchy, error handling becomes a guessing game: you can't know if a CSV parsing failure is temporary or structural, so you either suppress real issues or crash on transient ones.

Custom hierarchies also enable type-safe error handling and testability. When you raise `MissingRequiredFieldError` instead of `ValueError`, callers know the contract explicitly and can write tests expecting that specific exception. This pairs naturally with type hints and defensive programming—your IDE flags uncaught exceptions, and your test suite verifies behavior on known failure modes.

## Practice

**Problem:** Your `job_postings_fact` pipeline extracts job data from a REST API, transforms it, and loads into a data warehouse. The API sometimes returns malformed JSON, the database connection occasionally times out, and salary values are sometimes missing or invalid. You need to handle these failures differently: API errors should trigger a retry loop, missing required fields should log and skip the row, and invalid data types should halt and alert.

```python
# Custom exception hierarchy
class PipelineError(Exception):
    """Base exception for all pipeline failures."""
    pass

class SourceError(PipelineError):
    """Raised when extracting from source fails (API, file, etc.)."""
    pass

class APIConnectionError(SourceError):
    """Raised when API is unreachable or times out. Typically recoverable."""
    pass

class MalformedDataError(SourceError):
    """Raised when source data format is invalid (bad JSON, corrupt CSV)."""
    pass

class TransformError(PipelineError):
    """Raised during transformation (validation, type coercion, business rules)."""
    pass

class MissingRequiredFieldError(TransformError):
    """Raised when required field is absent. Row-level; can skip."""
    pass

class InvalidDataTypeError(TransformError):
    """Raised when field type cannot be coerced. Indicates schema mismatch."""
    pass

class LoadError(PipelineError):
    """Raised when inserting into warehouse fails."""
    pass

# Usage in extraction
import requests
import json

def extract_job_postings(api_url: str, max_retries: int = 3) -> list[dict]:
    for attempt in range(max_retries):
        try:
            response = requests.get(api_url, timeout=10)
            response.raise_for_status()
            return response.json()
        except requests.Timeout as e:
            if attempt == max_retries - 1:
                raise APIConnectionError(f"API timeout after {max_retries} retries") from e
        except json.JSONDecodeError as e:
            raise MalformedDataError(f"Invalid JSON from API: {e}") from e

# Usage in transformation
from datetime import datetime

def transform_job_posting(raw_row: dict) -> dict:
    required_fields = ['job_id', 'job_title_short', 'job_posted_date']
    
    # Check required fields
    for field in required_fields:
        if field not in raw_row or raw_row[field] is None:
            raise MissingRequiredFieldError(f"Missing required field: {field}")
    
    # Coerce types with specific exceptions
    try:
        job_id = int(raw_row['job_id'])
    except (ValueError, TypeError) as e:
        raise InvalidDataTypeError(f"job_id must be int, got {type(raw_row['job_id'])}: {e}") from e
    
    try:
        salary = float(raw_row.get('salary_year_avg') or 0)
    except ValueError as e:
        raise InvalidDataTypeError(f"salary_year_avg must be numeric: {e}") from e
    
    try:
        posted_date = datetime.strptime(raw_row['job_posted_date'], '%Y-%m-%d').date()
    except ValueError as e:
        raise InvalidDataTypeError(f"job_posted_date must be YYYY-MM-DD format: {e}") from e
    
    return {
        'job_id': job_id,
        'job_title_short': str(raw_row['job_title_short']),
        'salary_year_avg': salary,
        'job_work_from_home': bool(raw_row.get('job_work_from_home', False)),
        'job_posted_date': posted_date,
        'job_location': str(raw_row.get('job_location', 'Unknown'))
    }

# Main pipeline with different
