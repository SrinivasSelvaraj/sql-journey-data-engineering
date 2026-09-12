---
date: 2026-09-12
phase: python
topic: Dataclass validation and pydantic for pipeline schemas
---

# Dataclass validation and pydantic for pipeline schemas

*Python for data engineering*

## Concept

Pydantic and dataclass validation automatically enforce type correctness and constraints on pipeline inputs, preventing silent data corruption downstream. Without validation, a salary_year_avg of `"not_a_number"` or a job_posted_date as an integer timestamp will either crash your pipeline unexpectedly or propagate garbage through your models. Validation acts as a contract: it makes schema assumptions explicit and fails fast at ingestion rather than during analysis.

Pydantic (via `BaseModel`) is more powerful—it coerces types, runs custom validators, and generates clean error messages. Python's `dataclass` with `field()` validators is lighter but requires manual checking. For production pipelines ingesting external data (APIs, CSV, databases), Pydantic catches malformed records immediately, logs them clearly, and lets you decide whether to skip, retry, or fail the job.

The cost is minimal: a small schema file replaces implicit assumptions scattered through your code. It makes tests deterministic because you control exactly what invalid input looks like, and it documents your pipeline's expectations in code.

## Practice

**Problem:** Your pipeline reads job postings from an API. Some records have `salary_year_avg` as `null`, missing `job_location`, or `job_posted_date` in milliseconds instead of ISO format. Without validation, these slip into your warehouse and corrupt downstream reports.

```python
from pydantic import BaseModel, Field, field_validator
from datetime import date
from typing import Optional

class JobPostingFact(BaseModel):
    job_id: int
    job_title_short: str
    salary_year_avg: Optional[float] = None  # Allow null
    job_work_from_home: bool
    job_posted_date: date
    job_location: str
    
    @field_validator('job_location')
    @classmethod
    def location_not_empty(cls, v):
        if not v or not v.strip():
            raise ValueError('job_location cannot be empty')
        return v.strip()
    
    @field_validator('salary_year_avg')
    @classmethod
    def salary_positive(cls, v):
        if v is not None and v <= 0:
            raise ValueError('salary must be positive or null')
        return v

# Usage in pipeline
raw_record = {"job_id": 123, "job_title_short": "Engineer", 
              "salary_year_avg": 95000, "job_work_from_home": True,
              "job_posted_date": "2024-01-15", "job_location": "  NYC  "}

validated = JobPostingFact(**raw_record)  # Coerces date string, strips whitespace
# validated.job_location == "NYC"

# Bad record fails loudly with clear error:
bad = JobPostingFact(**{"job_id": 456, ..., "job_location": ""})  
# ValidationError: job_location cannot be empty
```

## Notes

- **Type coercion saves time:** Pydantic auto-converts `"2024-01-15"` to `date` and `"true"` to boolean—you don't need explicit casting in your ingestion logic.
- **Chain validators to SQL constraints:** Each Pydantic validator mirrors a NOT NULL, CHECK, or UNIQUE constraint you'd add to your warehouse schema; validation is documentation.
- **Common mistake:** Leaving optional fields as required; use `Optional[T]` and default values explicitly so missing data doesn't cause pipeline failure if the business allows it.
- **Connects to:** Error handling and retry logic (which records to skip/dead-letter), unit testing (fixtures with known-valid and invalid records), and schema evolution (when fields change, validators catch old formats).
- **Revisit when:** Adding enums for closed-set fields (e.g., job_title_short should be one of 10 known values), or using `Annotated` for more complex constraints without writing custom validators.
