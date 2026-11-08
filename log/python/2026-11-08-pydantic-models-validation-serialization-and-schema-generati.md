---
date: 2026-11-08
phase: python
topic: Pydantic models: validation, serialization and schema generation
---

# Pydantic models: validation, serialization and schema generation

*Python for data engineering*

## Concept

Pydantic models enforce schema validation at parse time, catching malformed data before it enters your pipeline. Instead of discovering bad input deep in transformation logic, you declare types and constraints upfront—Pydantic validates against them automatically. This is critical in ETL: upstream sources are often messy (missing fields, wrong types, out-of-range values), and downstream consumers depend on predictable data shapes.

Without validation, a pipeline silently accepts `salary_year_avg: "Not disclosed"` or `job_posted_date: "2024-13-45"`, only failing hours later in aggregation or model training. Pydantic catches these at the entry point and tells you *exactly* what field broke and why. You also get schema generation and serialization for free—document your data contract, validate API responses, and serialize to JSON or database records in one model definition.

## Practice

**Problem:** You're ingesting job posting records from an API that sometimes sends nulls, malformed dates, negative salaries, and extra fields. You need to reject invalid records without crashing the pipeline, validate constraints (salary > 0, date not in future), and load only clean records to the warehouse.

```python
from pydantic import BaseModel, Field, field_validator
from datetime import date
from typing import Optional

class JobPosting(BaseModel):
    job_id: int
    job_title_short: str
    salary_year_avg: Optional[int] = None
    job_work_from_home: bool
    job_posted_date: date
    job_location: str
    
    model_config = {"extra": "forbid"}  # reject unknown fields
    
    @field_validator("salary_year_avg")
    @classmethod
    def validate_salary(cls, v):
        if v is not None and v < 0:
            raise ValueError("salary must be non-negative")
        return v
    
    @field_validator("job_posted_date")
    @classmethod
    def validate_date_not_future(cls, v):
        if v > date.today():
            raise ValueError("posted date cannot be in future")
        return v

# Usage in pipeline
raw_records = [
    {"job_id": 1, "job_title_short": "Data Engineer", "salary_year_avg": 120000, 
     "job_work_from_home": True, "job_posted_date": "2024-01-15", "job_location": "Remote"},
    {"job_id": 2, "job_title_short": "Analyst", "salary_year_avg": -50000,  # invalid
     "job_work_from_home": False, "job_posted_date": "2024-01-20", "job_location": "NYC"},
]

valid_records = []
for record in raw_records:
    try:
        validated = JobPosting(**record)
        valid_records.append(validated.model_dump(mode="python"))
    except ValueError as e:
        print(f"Skipped record {record.get('job_id')}: {e}")

# valid_records now contains only clean data safe for warehouse load
```

## Notes

- **Serialization modes matter:** use `mode="python"` for dicts/Pandas, `mode="json"` for APIs; `model_dump_json()` for direct JSON output.
- **Field constraints belong in the model:** `Field(gt=0, le=999999)` for salary bounds is clearer and safer than checking in transform logic.
- **Optional vs. required is a contract:** distinguish between nullable fields and missing-field errors; use `Optional[int] = None` explicitly, not `int | None = None`.
- **Connect to testing:** Pydantic models are excellent test fixtures—generate valid examples with `model_validate()` or factory libraries like `factory_boy` paired with Pydantic.
- **Adjacent topics:** JSON Schema generation (`model_json_schema()`), Pydantic in FastAPI request validation, and ORM integration (SQLAlchemy with Pydantic) all build on the same validation layer.
