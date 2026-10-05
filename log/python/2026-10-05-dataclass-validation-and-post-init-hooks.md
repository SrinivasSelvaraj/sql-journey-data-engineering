---
date: 2026-10-05
phase: python
topic: Dataclass validation and post-init hooks
---

# Dataclass validation and post-init hooks

*Python for data engineering*

## Concept

Dataclass validation and `__post_init__` hooks enforce data integrity at object creation time, catching invalid states before they propagate through your pipeline. Without validation, a negative salary or malformed date string silently corrupts your fact table load, and you only discover it after ingestion. `__post_init__` runs immediately after `__init__`, making it the ideal checkpoint to normalize fields (strip whitespace, parse dates), apply business rules (salary >= 0, location not null), and raise typed exceptions that fail loudly and fast.

This matters especially in ETL where input schemas are loosely controlled—CSV headers shift, third-party APIs change formats, and bad records arrive daily. By validating at the dataclass level, you centralize guardrails, make pipeline code testable (you can unit-test validation logic in isolation), and produce predictable error messages that help operators debug upstream issues quickly.

## Practice

**Problem:** You're loading job posting facts from a CSV with inconsistent formatting. Some rows have negative salaries (data entry errors), dates in mixed formats, and whitespace-padded job titles. You need to validate and normalize these fields before inserting into the fact table.

```python
from dataclasses import dataclass
from datetime import datetime
from typing import Optional

@dataclass
class JobPostingFact:
    job_id: int
    job_title_short: str
    salary_year_avg: Optional[float]
    job_work_from_home: bool
    job_posted_date: datetime
    job_location: str
    
    def __post_init__(self):
        # Normalize string fields
        self.job_title_short = self.job_title_short.strip()
        self.job_location = self.job_location.strip()
        
        # Validate salary
        if self.salary_year_avg is not None and self.salary_year_avg < 0:
            raise ValueError(f"salary_year_avg must be non-negative, got {self.salary_year_avg}")
        
        # Parse and validate date
        if isinstance(self.job_posted_date, str):
            try:
                self.job_posted_date = datetime.fromisoformat(self.job_posted_date.replace('Z', '+00:00'))
            except ValueError as e:
                raise ValueError(f"job_posted_date '{self.job_posted_date}' does not match ISO format: {e}")
        
        # Validate required fields
        if not self.job_title_short:
            raise ValueError("job_title_short cannot be empty")
        if not self.job_location:
            raise ValueError("job_location cannot be empty")

# Usage in pipeline
try:
    row = JobPostingFact(
        job_id=123,
        job_title_short="  Data Engineer  ",
        salary_year_avg=-50000,  # Will raise
        job_work_from_home=True,
        job_posted_date="2024-01-15T00:00:00Z",
        job_location="Remote"
    )
except ValueError as e:
    print(f"Validation error: {e}")
    # Log and skip this row, continue processing
```

## Notes

- **Type coercion in `__post_init__`** can hide bugs; only coerce fields you control (dates, trimmed strings). If type hints say `int` but you receive a string, let it fail—don't silently convert.
- **Order matters**: validate normalization (trim, parse) before applying business rules (check salary >= 0), so error messages reflect intent, not intermediate state.
- **Connection to schema validation**: dataclass validation is local and instance-level; pair it with `pydantic` (or `dataclasses-validate`) for declarative, reusable schemas that scale to hundreds of fields.
- **Testing validation** is cheap; write unit tests that directly instantiate dataclasses with bad inputs and assert the right exception is raised. This becomes your living documentation of pipeline guardrails.
- **Revisit when**: adding conditional logic (e.g., "if remote, location must be 'Remote'; if on-site, must be a real city"), where you need cross-field validation that `__post_init__` alone can't express cleanly—consider a separate `validate()` method or a validator class.
