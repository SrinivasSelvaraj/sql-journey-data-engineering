---
date: 2026-08-09
phase: python
topic: Structured logging instead of print
---

# Structured logging instead of print

*Python for data engineering*

## Concept

Structured logging replaces ad-hoc print statements with a logging framework that captures context, severity, and machine-readable fields. In data pipelines, this means replacing `print(f"Processing row {i}")` with `logger.info("row_processed", extra={"row_id": i, "table": "staging"})`. Print statements disappear in logs, mix stdout with stderr, offer no timestamps or levels, and are nearly impossible to aggregate or alert on when running in production (containers, orchestrators, cloud jobs).

Without structured logging, you lose observability: you can't debug why a batch job silently dropped 10k records, can't correlate failures across services, and can't replay what the pipeline saw at 3am. Print-based debugging scales only to your laptop. Structured logging with levels (DEBUG, INFO, WARNING, ERROR) and field extraction lets you filter, search, and monitor in real time using tools like ELK, Datadog, or cloud logging APIs.

## Practice

**Problem:** A job posting ETL loads 50k records daily into `job_postings_fact`. Some records have null salary_year_avg; others have impossible dates (future dates, year 1900). You need to log how many records failed validation, which fields caused failures, and which jobs succeeded—all queryable later.

```python
import logging
import json
from datetime import datetime
from typing import Optional

logger = logging.getLogger(__name__)
handler = logging.StreamHandler()
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
handler.setFormatter(formatter)
logger.addHandler(handler)
logger.setLevel(logging.INFO)

def validate_job_posting(row: dict) -> tuple[bool, Optional[str]]:
    """Return (is_valid, error_message)"""
    if not row.get("salary_year_avg") or row["salary_year_avg"] <= 0:
        return False, "missing_or_negative_salary"
    
    try:
        posted = datetime.strptime(row["job_posted_date"], "%Y-%m-%d")
        if posted > datetime.now() or posted.year < 2020:
            return False, "date_out_of_range"
    except ValueError:
        return False, "date_parse_error"
    
    return True, None

def load_job_postings(records: list[dict]) -> dict:
    """Load records into job_postings_fact, log all outcomes."""
    stats = {"loaded": 0, "failed": 0, "errors": {}}
    
    for idx, row in enumerate(records):
        is_valid, error = validate_job_posting(row)
        
        if is_valid:
            # Insert into DB here
            stats["loaded"] += 1
            logger.info(
                "job_posted_loaded",
                extra={
                    "job_id": row["job_id"],
                    "job_title": row["job_title_short"],
                    "salary": row["salary_year_avg"],
                    "event": "success"
                }
            )
        else:
            stats["failed"] += 1
            stats["errors"][error] = stats["errors"].get(error, 0) + 1
            logger.warning(
                "job_posting_validation_failed",
                extra={
                    "job_id": row["job_id"],
                    "validation_error": error,
                    "row_index": idx,
                    "event": "validation_failed"
                }
            )
    
    logger.info(
        "load_job_postings_complete",
        extra={
            "total_records": len(records),
            "loaded": stats["loaded"],
            "failed": stats["failed"],
            "error_breakdown": stats["errors"]
        }
    )
    return stats
```

## Notes

- **Mistake**: logging full DataFrames or large objects—use only the fields you need to query; store IDs/keys, not blobs.
- **Mistake**: using `logger.exception()` inside except blocks without context; always include the row/job ID so you can trace failures.
- **Connection**: pairs with metrics/instrumentation (log counts, then graph them); complements tracing in distributed systems to follow a request across services.
- **Worth revisiting**: log aggregation tools (grep vs. centralized logging), log levels and when to use each, sampling large-scale logs to control cost.
- **Adjacent**: error handling patterns (fail fast vs. continue-and-log), retry logic with exponential backoff + structured logs, and schema validation (Pydantic, Great Expectations).
