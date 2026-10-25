---
date: 2026-10-25
phase: python
topic: Logging configuration and structured JSON logs
---

# Logging configuration and structured JSON logs

*Python for data engineering*

## Concept

Logging configuration and structured JSON logs are critical for data pipelines because unstructured text logs become unqueryable nightmares at scale. A well-configured logger outputs JSON with consistent fields (timestamp, level, message, context) that can be indexed, filtered, and aggregated by tools like ELK, Datadog, or CloudWatch. Without it, you're grepping logfiles manually when a pipeline fails at 3am in production.

In data engineering specifically, structured logging lets you track data lineage, record row counts and transformation times, and correlate failures across multiple pipeline stages. A single pipeline run might spawn dozens of tasks; JSON logs with a shared `run_id` or `job_id` field let you reconstruct the entire execution flow. Without this, you lose visibility into which transformation corrupted data and when.

Broken logging surfaces as mysterious failures: "the pipeline failed" tells you nothing; "transformation stage_3 wrote 0 rows when expecting 1.2M, duration 1843ms, input_rows=1200000" tells you everything. Silence in logs is often worse than errors—a task that silently produces no output can lurk undetected.

## Practice

**Problem:** You're loading job postings into `job_postings_fact` and need to log each stage (extraction, validation, load) with row counts, durations, and any data quality issues. If validation fails for salary data, you want the exact count of rejected rows and the reason why logged as JSON.

```python
import logging
import json
from datetime import datetime
import time
from typing import Optional

# Configure structured JSON logging
class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_obj = {
            "timestamp": datetime.utcnow().isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "run_id": getattr(record, "run_id", None),
            "stage": getattr(record, "stage", None),
        }
        if record.exc_info:
            log_obj["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_obj)

handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logger = logging.getLogger("pipeline")
logger.addHandler(handler)
logger.setLevel(logging.INFO)

def load_job_postings(run_id: str, csv_path: str) -> dict:
    """Load and validate job postings with structured logging."""
    
    # Extract
    start = time.time()
    rows = []
    try:
        with open(csv_path) as f:
            rows = [line.strip().split(",") for line in f][1:]  # skip header
        duration = time.time() - start
        logger.info(
            f"Extracted {len(rows)} job postings",
            extra={"run_id": run_id, "stage": "extract", "row_count": len(rows), "duration_ms": int(duration * 1000)}
        )
    except Exception as e:
        logger.error(f"Extract failed: {e}", extra={"run_id": run_id, "stage": "extract"}, exc_info=True)
        return {"success": False}
    
    # Validate salary
    start = time.time()
    valid, rejected = [], []
    for row in rows:
        try:
            salary = float(row[2])
            if salary > 0:
                valid.append(row)
            else:
                rejected.append((row, "salary_not_positive"))
        except ValueError:
            rejected.append((row, "salary_not_numeric"))
    
    duration = time.time() - start
    logger.info(
        f"Validated {len(valid)} rows, rejected {len(rejected)}",
        extra={
            "run_id": run_id,
            "stage": "validate",
            "valid_rows": len(valid),
            "rejected_rows": len(rejected),
            "rejection_reasons": {reason: sum(1 for _, r in rejected if r == reason) for _, reason in rejected},
            "duration_ms": int(duration * 1000)
        }
    )
    
    # Load (simulated)
    start = time.time()
    logger.info(
        f"Loaded {len(valid)} rows to job_postings_fact",
        extra={"run_id": run_id, "stage": "load", "inserted_rows": len(valid), "duration_ms": int((time.time() - start) * 1000)}
    )
    
    return {"success": True, "inserted": len(valid), "rejected": len(rejected)}

# Usage
load_job_postings(run_id="run_20250115_001", csv_path="jobs.csv")
```

## Notes

- **Don't log to plain text in production:** Always structure as JSON or a consistent format; your future self debugging at 2am will thank you. Plain text logs become
