---
date: 2026-11-08
phase: python
topic: Logging best practices: levels, handlers and structured logs
---

# Logging best practices: levels, handlers and structured logs

*Python for data engineering*

## Concept

Logging is instrumentation that tracks what your pipeline does at runtime—not just when it breaks. Python's `logging` module provides **levels** (DEBUG, INFO, WARNING, ERROR, CRITICAL) to separate noise from signal, **handlers** (file, stream, syslog) to route messages to the right place, and **structured logs** (JSON-formatted key-value pairs) to make logs machine-parseable instead of unstructable walls of text.

In data pipelines, unstructured logs hide critical context: *Which* extract failed? How many rows were skipped? What was the input shape? Structured logging with correlation IDs, row counts, and transformation stages lets you grep logs like a database and alerts on exact conditions. Without it, you spend hours reading walls of text or miss silent data quality drops entirely.

The standard mistake is printing instead of logging (`print()` bypasses levels, handlers, and timestamps) or logging only errors. A production pipeline should emit INFO for task boundaries (extract started, transform complete, load succeeded) and DEBUG for intermediate states, so you can retroactively understand a failed run without re-running it.

## Practice

**Problem:** Your `job_postings_fact` loader runs nightly but sometimes produces zero rows with no warning. You need to log extraction, validation, and load counts at INFO level, plus row-level issues at DEBUG, so you can spot silent failures and diagnose schema mismatches.

```python
import logging
import json
from datetime import datetime

# Configure structured logging
logger = logging.getLogger(__name__)
handler = logging.FileHandler('pipeline.log')
formatter = logging.Formatter(
    '{"timestamp": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s"}'
)
handler.setFormatter(formatter)
logger.addHandler(handler)
logger.setLevel(logging.DEBUG)

def load_job_postings(source_path, target_table):
    run_id = datetime.now().isoformat()
    
    # Extract phase
    logger.info(json.dumps({
        "event": "extract_start",
        "run_id": run_id,
        "source": source_path
    }))
    
    df = pd.read_csv(source_path)
    extracted_count = len(df)
    logger.info(json.dumps({
        "event": "extract_complete",
        "run_id": run_id,
        "row_count": extracted_count
    }))
    
    # Validation phase
    if extracted_count == 0:
        logger.error(json.dumps({
            "event": "validation_failed",
            "run_id": run_id,
            "reason": "no_rows_extracted"
        }))
        return False
    
    invalid_rows = df[df['salary_year_avg'].isna() | (df['job_posted_date'].isna())].shape[0]
    valid_count = extracted_count - invalid_rows
    logger.info(json.dumps({
        "event": "validation_complete",
        "run_id": run_id,
        "valid_rows": valid_count,
        "invalid_rows": invalid_rows
    }))
    
    logger.debug(json.dumps({
        "event": "sample_validation",
        "run_id": run_id,
        "columns": list(df.columns),
        "dtypes": {k: str(v) for k, v in df.dtypes.items()}
    }))
    
    # Load phase
    logger.info(json.dumps({
        "event": "load_start",
        "run_id": run_id,
        "target": target_table,
        "row_count": valid_count
    }))
    
    # ... actual insert logic ...
    
    logger.info(json.dumps({
        "event": "load_complete",
        "run_id": run_id,
        "rows_loaded": valid_count
    }))
    return True
```

## Notes

- **Structured logs enable alerting:** Parse `"event": "validation_failed"` with a log aggregator (ELK, Datadog) to trigger alerts on zero-row extracts or threshold breaches, not just crashes.
- **Correlation IDs (run_id) are essential:** One logical pipeline run may spawn multiple processes/services; include a `run_id` in every log so you can `grep` a single run's story across machines.
- **DEBUG vs. INFO splits:** INFO is for humans/ops (task boundaries, counts, decisions); DEBUG is for engineers (row samples, intermediate state, full payloads). Toggle with `logger.setLevel()` without redeploying.
- **Avoid logging secrets:** Never log API keys, passwords, or unredacted PII. Use `message = message.replace(api_key, '***')` or a custom filter before writing.
- **Connect to testing:** Unit tests should mock `logger` calls and assert on log events, not just return values—catch silent bugs like "function returned True but extracted 0 rows."
