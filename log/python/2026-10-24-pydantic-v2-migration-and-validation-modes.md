---
date: 2026-10-24
phase: python
topic: Pydantic v2 migration and validation modes
---

# Pydantic v2 migration and validation modes

*Python for data engineering*

## Concept

Pydantic v2 introduces stricter validation modes and a redesigned validation engine that breaks backward compatibility with v1 schemas. The two key modes are **strict** (rejects type coercion, requires exact types) and **lax** (permits reasonable conversions like `"123"` → `123`). This matters in data pipelines because bad input—malformed dates, string salaries, null booleans from databases—will either halt your pipeline (strict) or silently transform (lax), and you must choose which failure mode suits your use case. Without explicit validation mode configuration, Pydantic v2 defaults to lax validation but may surprise you when `"2024-01-15"` silently becomes a date object instead of raising an error, or when a missing job_location gets coerced to None unexpectedly. In data engineering, this is critical: you want validation to be *deliberate*, not magical.

## Practice

**Problem:** Your ingestion pipeline reads job postings from a messy CSV where `salary_year_avg` arrives as strings (`"95000"`, `"N/A"`), `job_posted_date` is sometimes `"2024-01-15"` and sometimes `null`, and `job_work_from_home` is occasionally `"yes"`, `"1"`, or blank. You need validation that catches malformed salary and rejects invalid dates, but tolerates reasonable conversions.

```python
from pydantic import BaseModel, field_validator, ConfigDict
from datetime import date
from typing import Optional

class JobPostingsFact(BaseModel):
    model_config = ConfigDict(validate_default=True)
    
    job_id: int
    job_title_short: str
    salary_year_avg: Optional[int] = None
    job_work_from_home: bool
    job_posted_date: date
    job_location: str
    
    @field_validator('salary_year_avg', mode='before')
    @classmethod
    def parse_salary(cls, v):
        if v is None or v == 'N/A' or v == '':
            return None
        if isinstance(v, str):
            try:
                return int(v)
            except ValueError:
                raise ValueError(f"Invalid salary: {v}")
        return v
    
    @field_validator('job_work_from_home', mode='before')
    @classmethod
    def parse_remote(cls, v):
        if isinstance(v, bool):
            return v
        if isinstance(v, str):
            return v.lower() in ('yes', 'true', '1', 't')
        return bool(v)

# Usage in pipeline
row = {'job_id': 1, 'job_title_short': 'Data Engineer', 'salary_year_avg': '95000',
       'job_work_from_home': 'yes', 'job_posted_date': '2024-01-15', 'job_location': 'New York'}
posting = JobPostingsFact(**row)  # Succeeds, coerces sensibly
```

## Notes

- **Validation modes are per-field, not global:** Use `mode='before'` to intercept raw input before Pydantic's type coercion; `mode='after'` to validate the already-coerced type. This gives surgical control over what transforms are acceptable.
- **`ConfigDict(validate_default=True)` is essential for pipelines:** Without it, default values skip validation, allowing invalid data to hide in your schema until runtime.
- **v1 to v2 breaking change:** `validator()` is now `field_validator()`, and validation signature changed—old code will silently do the wrong thing. Check your imports and decorator names before merging.
- **Adjacent: relate this to type hints + testing:** Strict validation pairs with property-based testing (Hypothesis) to catch edge cases; lax validation requires explicit integration tests on actual messy data.
- **Revisit when:** Adding new fields to production schemas, debugging "why did this bad value slip through?", or comparing validation cost vs. data quality tradeoff.
