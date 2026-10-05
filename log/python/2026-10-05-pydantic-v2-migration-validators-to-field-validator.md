---
date: 2026-10-05
phase: python
topic: Pydantic v2 migration: validators to field_validator
---

# Pydantic v2 migration: validators to field_validator

*Python for data engineering*

## Concept

Pydantic v2 replaced the `@validator` decorator with `@field_validator`, shifting from class-method decoration to a more explicit, composable pattern. In v1, validators were called during model instantiation with access to `values` dict and other fields; v2 validators receive individual field values and require you to specify which fields they apply to via arguments, making the dependency graph clearer and validation order more predictable.

This matters because Pydantic is the standard tool for validating messy input in data pipelines—API responses, CSV uploads, database records. When migrating legacy code or building new pipelines, using v2's `field_validator` makes your schema self-documenting: you can instantly see which fields have constraints and why, and you avoid silent failures from misconfigured validators. Without proper migration, you'll hit `AttributeError` or silent no-ops when v1 code runs under v2.

The key breaking change: v1 `@validator('field1', 'field2')` becomes `@field_validator('field1', 'field2')` in v2, *but* the function signature changes from `(cls, v, values)` to `(cls, v, info)`, and cross-field validation now requires `mode='before'` or explicit field access via `info.data`. Salary and location validation examples are common pitfalls.

## Practice

**Problem:** You're ingesting `job_postings_fact` records from an upstream API. The API sometimes sends `salary_year_avg` as a string (e.g., `"120000"`), sometimes as an integer, and sometimes null. It also sends `job_location` with leading/trailing whitespace and occasionally missing country codes. You need to normalize salary to a non-negative integer, strip and uppercase location, and reject any posting without both salary and a valid location.

```python
from pydantic import BaseModel, field_validator
from datetime import date

class JobPostingFact(BaseModel):
    job_id: int
    job_title_short: str
    salary_year_avg: int
    job_work_from_home: bool
    job_posted_date: date
    job_location: str

    @field_validator('salary_year_avg', mode='before')
    @classmethod
    def validate_salary(cls, v):
        if v is None:
            raise ValueError('salary_year_avg cannot be null')
        if isinstance(v, str):
            v = int(v)
        if v < 0:
            raise ValueError('salary_year_avg must be non-negative')
        return v

    @field_validator('job_location')
    @classmethod
    def validate_location(cls, v):
        if not v or not v.strip():
            raise ValueError('job_location cannot be empty')
        return v.strip().upper()
```

## Notes

- **mode='before' vs default**: Use `mode='before'` when you need to coerce types (string → int) before Pydantic's type checking; default mode runs after. For location, no mode needed because strip/upper happen post-parse.

- **Cross-field validation**: If you need to validate salary *relative to* job_title (e.g., reject entry-level roles with $500k), use `model_validator` with `mode='after'` instead—it runs after all fields are validated and gives you access to the entire model instance via `info.data` or `self`.

- **Common mistake**: Forgetting that v2 `field_validator` on multiple fields still receives one field value at a time—don't try to unpack or iterate `v`. Write separate validators for each logical constraint or use `model_validator` for many-to-many relationships.

- **Testing entry point**: Unit test validators by instantiating the model with bad input and catching `ValidationError`. This is where you catch API surprises early, before they corrupt your warehouse.

- **Adjacent: Pydantic's ConfigDict**: v2 moved config from nested `Config` class to `model_config = ConfigDict(...)`. If your schema needs to coerce `orm_mode=True` (now `from_attributes=True`) or allow population by field alias, migrate that too.
