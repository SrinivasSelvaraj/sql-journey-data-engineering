---
date: 2026-11-08
phase: python
topic: FastAPI: building REST APIs for data engineering services
---

# FastAPI: building REST APIs for data engineering services

*Python for data engineering*

## Concept

FastAPI is a modern Python web framework for building REST APIs with automatic input validation, type hints, and OpenAPI documentation. For data engineering services—such as ETL job status endpoints, data catalog APIs, or query interfaces—FastAPI enforces strong typing at the request/response boundary, catching malformed input before it reaches your pipeline logic. Without this validation layer, bad data shapes (wrong types, missing fields, out-of-range values) propagate downstream, causing silent failures in transformations or crashes in production jobs.

The framework integrates Pydantic for schema validation, meaning you define request models once and get automatic serialization, deserialization, and error responses. This is critical when exposing data pipelines to external services or teams: a typo in a query parameter or a null salary field should fail loudly at the API boundary, not corrupt your fact table. FastAPI also generates interactive API documentation (Swagger UI) automatically, making your service self-documenting and testable without curl scripts.

## Practice

**Problem:** Build a FastAPI endpoint that accepts job posting filters (title keyword, location, minimum salary) and returns matching records from `job_postings_fact`. Validate that salary is non-negative, location is not empty, and return a typed list response. Reject requests with invalid types or missing required fields.

```sql
-- Supporting query logic (called from the FastAPI handler)
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM job_postings_fact
WHERE (job_title_short ILIKE '%' || %s || '%' OR %s IS NULL)
  AND (job_location = %s OR %s IS NULL)
  AND (salary_year_avg >= %s OR %s IS NULL)
ORDER BY job_posted_date DESC
LIMIT 100;
```

```python
from fastapi import FastAPI, Query, HTTPException
from pydantic import BaseModel, Field, field_validator
from typing import Optional, List
from datetime import date

app = FastAPI()

class JobPostingResponse(BaseModel):
    job_id: int
    job_title_short: str
    salary_year_avg: Optional[float]
    job_work_from_home: bool
    job_posted_date: date
    job_location: str

class JobFilterRequest(BaseModel):
    title_keyword: Optional[str] = Field(None, min_length=1, max_length=100)
    location: Optional[str] = Field(None, min_length=1, max_length=100)
    min_salary: Optional[float] = Field(None, ge=0)

    @field_validator('min_salary')
    @classmethod
    def salary_not_negative(cls, v):
        if v is not None and v < 0:
            raise ValueError('Salary cannot be negative')
        return v

@app.get("/jobs", response_model=List[JobPostingResponse])
def search_jobs(
    title: Optional[str] = Query(None, min_length=1),
    location: Optional[str] = Query(None, min_length=1),
    min_salary: Optional[float] = Query(None, ge=0)
):
    """Search job postings with optional filters."""
    try:
        # Pseudo-code: execute parameterized query
        results = execute_query(
            "SELECT ... FROM job_postings_fact WHERE ...",
            (title, location, min_salary)
        )
        return [JobPostingResponse(**row) for row in results]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
```

## Notes

- **Type hints are validation contracts**: Pydantic automatically rejects `{"min_salary": "not_a_number"}` before your code runs; this prevents type confusion bugs in downstream transformations.
- **Use `Field()` constraints** (min_length, ge, le) to enforce business rules at the API boundary; don't rely on SQL `CHECK` constraints alone—fail fast at the source.
- **Parameterized queries are non-negotiable**: even with FastAPI validation, always use placeholders (`%s`, `?`) to prevent SQL injection from unexpected input patterns.
- **Test with `TestClient`**: FastAPI provides `from fastapi.testclient import TestClient` for unit testing endpoints without spinning up a server; pair with pytest for CI/CD.
- **Adjacent topics**: async handlers (`async def`) for I/O-bound queries, dependency injection for database connections, middleware for logging/auth, and Pydantic v2's `model_validate()` for custom deserialization logic.
