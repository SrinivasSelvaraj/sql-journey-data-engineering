---
date: 2026-08-27
phase: python
topic: Pydantic: data validation, coercion and schema evolution
---

# Pydantic: data validation, coercion and schema evolution

*Python for data engineering*

## Concept

Pydantic is a Python library that validates data at parse time, ensuring your pipeline only processes records matching a declared schema. It coerces types automatically (string "42" → int 42, "2024-01-15" → date object) and raises errors immediately when data violates constraints—before bad rows corrupt downstream logic or databases. This matters because raw data is messy: missing fields, wrong types, out-of-range values, and malformed strings are the norm, not exceptions. Without validation, these errors propagate silently or crash your pipeline at unpredictable points. Pydantic catches them early with clear error messages, making debugging tractable and letting you decide whether to reject, coerce, or skip bad records.

Schema evolution—adding fields, changing types, or relaxing constraints—is inevitable as requirements shift. Pydantic's `ConfigDict(extra='forbid'|'allow'|'ignore')` settings let you handle unknown fields gracefully, and `Field(default=...)` makes optional fields explicit. Versioning your models and using union types allows old and new data to coexist during transitions. In data pipelines, this prevents the brittle coupling where a single upstream schema change cascades failures downstream.

## Practice

**Problem:** Your job postings ingestion receives records where `salary_year_avg` comes as string or null, `job_posted_date` may be ISO or US format, and sometimes extra fields appear. You need to validate, coerce types, and reject records with missing `job_id` or `job_title_short` without stopping the entire pipeline.

```python
from pydantic import BaseModel, Field, field_validator, ConfigDict
from datetime import date
from typing import Optional

class JobPostingFact(BaseModel):
    model_config = ConfigDict(extra='ignore', str_strip_whitespace=True)
    
    job_id: int
    job_title_short: str
    salary_year_avg: Optional[int] = None
    job_work_from_home: bool
    job_posted_date: date
    job_location: str
    
    @field_validator('salary_year_avg', mode='before')
    @classmethod
    def coerce_salary(cls, v):
        if v is None or v == '':
            return None
        if isinstance(v, str):
            return int(v.replace(',', ''))
        return int(v)
    
    @field_validator('job_posted_date', mode='before')
    @classmethod
    def parse_date(cls, v):
        if isinstance(v, date):
            return v
        # Try ISO format, then US format
        for fmt in ('%Y-%m-%d', '%m/%d/%Y'):
            try:
                return date.fromisoformat(v) if fmt == '%Y-%m-%d' else datetime.strptime(v, fmt).date()
            except ValueError:
                continue
        raise ValueError(f'Invalid date: {v}')

# In pipeline:
for raw_record in input_stream:
    try:
        validated = JobPostingFact(**raw_record)
        process(validated)
    except ValueError as e:
        logger.warning(f"Skipped record {raw_record.get('job_id')}: {e}")
```

## Notes

- **Type coercion order matters:** Pydantic validates in field declaration order; put validators with dependencies after their inputs.
- **`mode='before'` vs. default:** Use `mode='before'` to transform raw input before type checking; default mode validates after Pydantic's built-in coercion.
- **Schema versioning:** Keep old model versions in a `schemas.v1` module; use discriminated unions (`Discriminator(...)`) to route records to the correct parser.
- **`extra='forbid'` catches schema drift:** Fail fast on upstream changes; `extra='ignore'` is safer if you control only downstream and don't care about extra fields.
- **Connect to:** logging (log rejected records and their reasons), testing (parametrize tests with edge cases: nulls, wrong formats, boundary values), and data contracts (Pydantic schemas can document your pipeline's implicit contract with producers).
