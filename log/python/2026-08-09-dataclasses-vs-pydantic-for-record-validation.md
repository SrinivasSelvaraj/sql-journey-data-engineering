---
date: 2026-08-09
phase: python
topic: Dataclasses vs pydantic for record validation
---

# Dataclasses vs pydantic for record validation

*Python for data engineering*

## Concept

Dataclasses and Pydantic both define structured record schemas in Python, but they handle validation differently. **Dataclasses** (stdlib, Python 3.7+) are lightweight containers with optional type hints and no built-in validation—useful for simple, trusted data. **Pydantic** adds runtime validation, type coercion, and error reporting out of the box, catching malformed input before it corrupts your pipeline.

In data engineering, this distinction is critical. A CSV reader or API response may send `salary_year_avg` as a string `"150000"` instead of an integer, or `job_posted_date` in an unexpected format. Dataclasses will accept it and fail later when you try arithmetic or filtering. Pydantic validates on instantiation, raising `ValidationError` immediately with precise feedback about what failed and why.

Use **dataclasses** for internal, controlled schemas (e.g., between trusted functions). Use **Pydantic** at pipeline entry points—right after reading files, calling APIs, or accepting user input. This makes your pipeline robust: bad data is rejected early with clear signals, not silently corrupted.

## Practice

**Problem:** A CSV job postings feed arrives with `salary_year_avg` sometimes as string, sometimes missing, and `job_posted_date` in mixed formats (YYYY-MM-DD or MM/DD/YYYY). You need to validate and normalize records before loading into a fact table.

```python
from pydantic import BaseModel, field_validator
from datetime import date

class JobPostingRecord(BaseModel):
    job_id: int
    job_title_short: str
    salary_year_avg: int | None = None
    job_work_from_home: bool
    job_posted_date: date
    job_location: str

    @field_validator('salary_year_avg', mode='before')
    @classmethod
    def parse_salary(cls, v):
        if v is None or v == '':
            return None
        return int(float(str(v).replace(',', '')))

    @field_validator('job_posted_date', mode='before')
    @classmethod
    def parse_date(cls, v):
        if isinstance(v, date):
            return v
        for fmt in ('%Y-%m-%d', '%m/%d/%Y'):
            try:
                return date.fromisoformat(v) if fmt == '%Y-%m-%d' else date(*(map(int, v.split('/')[::-1])))
            except ValueError:
                continue
        raise ValueError(f"Cannot parse date: {v}")

# Usage in pipeline
for row in csv.DictReader(input_file):
    try:
        record = JobPostingRecord(**row)
        insert_into_job_postings_fact(record)
    except ValidationError as e:
        log_bad_record(row, e)  # isolate bad input, continue processing
```

## Notes

- **Common mistake:** Using dataclasses for external input and debugging type errors downstream instead of validating at ingestion. Move validation earlier in the pipeline.
- **Coercion vs. strictness:** Pydantic's `mode='before'` allows flexible parsing (string → int); use `mode='after'` to enforce strict types. Know which you need for each field.
- **Performance trade-off:** Pydantic validation adds ~microseconds per record; negligible for most pipelines but profile if processing millions/sec.
- **Adjacent topics:** This connects to schema enforcement (SQL CHECK constraints, dbt tests), error handling patterns (retry logic, dead-letter queues), and logging strategy for rejected records.
- **Worth revisiting:** Pydantic v2 changed validators significantly; check your version. Also explore `config.json_schema_extra` for generating data contracts and documentation from your schemas.
