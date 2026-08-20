---
date: 2026-08-20
phase: python
topic: Building a simple FastAPI endpoint for pipeline metadata
---

# Building a simple FastAPI endpoint for pipeline metadata

*Python for data engineering*

## Concept

A FastAPI endpoint for pipeline metadata is a typed, validated HTTP interface that exposes information about data pipelines—such as job name, last run time, row counts, or data quality metrics. Instead of querying logs or databases directly, you expose structured responses with Pydantic models, ensuring both the API contract and internal validation are explicit and fail loudly on bad input.

This matters because data pipelines are often black boxes to downstream consumers (analysts, dashboards, other services). Without a metadata API, teams fall back to ad-hoc queries, Slack messages, or checking timestamps in S3. With a proper endpoint, you document what data is fresh, whether a pipeline succeeded, and what transformations ran—and you do this in a way that survives misuse: wrong query parameters, missing fields, or unexpected null values are caught before they corrupt downstream logic.

Without it, bad input (a misspelled pipeline name, missing date, negative row count) either crashes a consumer's code or silently produces wrong results. A typed, validated endpoint makes those errors visible immediately and provides a single source of truth for pipeline health.

## Practice

**Problem:** Build a FastAPI endpoint that returns metadata for the job_postings_fact table—including job count, date range, and work-from-home percentage—but reject requests with invalid date ranges (end before start) and ensure all numeric fields are non-negative.

```python
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, field_validator
from datetime import date
from typing import Optional

app = FastAPI()

class PipelineMetadata(BaseModel):
    table_name: str
    total_jobs: int
    min_posted_date: date
    max_posted_date: date
    work_from_home_pct: float
    
    @field_validator("total_jobs")
    @classmethod
    def validate_total_jobs(cls, v):
        if v < 0:
            raise ValueError("total_jobs must be non-negative")
        return v
    
    @field_validator("work_from_home_pct")
    @classmethod
    def validate_pct(cls, v):
        if not (0 <= v <= 100):
            raise ValueError("work_from_home_pct must be between 0 and 100")
        return v

@app.get("/metadata/job_postings", response_model=PipelineMetadata)
def get_job_postings_metadata(
    start_date: Optional[date] = Query(None),
    end_date: Optional[date] = Query(None),
):
    if start_date and end_date and start_date > end_date:
        raise HTTPException(
            status_code=400,
            detail="start_date must be <= end_date"
        )
    
    # Query logic (pseudo-code)
    total = 42000
    wfh_pct = 37.5
    
    return PipelineMetadata(
        table_name="job_postings_fact",
        total_jobs=total,
        min_posted_date=date(2023, 1, 1),
        max_posted_date=date(2024, 12, 31),
        work_from_home_pct=wfh_pct,
    )
```

## Notes

- **Pydantic validators run on response models too:** even if your database query returns garbage, the response model will reject it before it reaches the client, preventing silent data corruption downstream.
- **Distinguish between user input validation (Query) and model validation:** Query parameters should be coerced/validated at the route level (start_date > end_date); field-level validators in the Pydantic model enforce invariants on the data itself (work_from_home_pct ∈ [0, 100]).
- **Use HTTPException with clear detail messages:** `detail="start_date must be <= end_date"` is far more helpful to a consumer than a 500 error or cryptic stack trace.
- **Connect this to schema versioning and monitoring:** metadata endpoints are often the first place to wire up alerts (e.g., if total_jobs drops 50% overnight, alert), and they benefit from versioning (e.g., `/v1/metadata/` vs `/v2/metadata/`) as your pipelines evolve.
- **Revisit: testing the endpoint with pytest and httpx, adding rate limiting for high-frequency metadata checks, and storing metadata in a real metadata store** (not just computing on-the-fly) so you can track historical pipeline performance.
