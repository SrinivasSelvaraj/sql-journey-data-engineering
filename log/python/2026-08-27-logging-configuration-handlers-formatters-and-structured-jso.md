---
date: 2026-08-27
phase: python
topic: Logging configuration: handlers, formatters and structured JSON
---

# Logging configuration: handlers, formatters and structured JSON

*Python for data engineering*

## Concept

Logging configuration in Python separates *where* logs go (handlers), *how* they look (formatters), and *what information* they contain (structured vs. unstructured). Handlers direct output to files, stdout, or external services; formatters control whether logs are plain text or machine-readable JSON. This matters in data pipelines because unstructured logs become useless at scale—you can't grep through 100GB of logs for the job_id that caused a salary calculation to fail. Structured JSON logging lets you parse, filter, and aggregate logs programmatically, turning debugging from archaeology into querying.

Without proper logging configuration, you lose context. A pipeline crashes silently, or errors are buried in stdout alongside 10,000 INFO messages. In production, you can't reproduce a bad transformation that happened at 2 AM. With handlers and formatters configured early, every step becomes traceable: you log the input row, the transformation rule applied, the output value, and the timestamp—all parseable JSON that lives in a log file or goes to a centralized system like ELK or Splunk.

## Practice

**Problem:** A data pipeline loads job postings from a CSV, calculates salary_year_avg from hourly_rate, and inserts into job_postings_fact. Some rows silently fail because hourly_rate is NULL or non-numeric. You need logs that record: the job_id, the raw hourly_rate value, whether it was skipped, and the final salary_year_avg inserted.

```python
import logging
import json
from datetime import datetime

# Configure handler and formatter
handler = logging.FileHandler('pipeline.log')
formatter = logging.Formatter(
    '%(message)s'  # We'll emit JSON, so don't use format string
)
handler.setFormatter(formatter)

logger = logging.getLogger('job_pipeline')
logger.addHandler(handler)
logger.setLevel(logging.INFO)

# Log as structured JSON
for row in input_rows:
    log_entry = {
        'timestamp': datetime.utcnow().isoformat(),
        'job_id': row['job_id'],
        'job_title_short': row['job_title_short'],
        'raw_hourly_rate': row.get('hourly_rate'),
        'status': 'pending'
    }
    
    try:
        salary = float(row['hourly_rate']) * 2080 if row['hourly_rate'] else None
        if salary is None:
            log_entry['status'] = 'skipped'
            log_entry['reason'] = 'null_hourly_rate'
            logger.info(json.dumps(log_entry))
            continue
        
        log_entry['salary_year_avg'] = salary
        log_entry['status'] = 'inserted'
        # INSERT into job_postings_fact
        logger.info(json.dumps(log_entry))
    except ValueError as e:
        log_entry['status'] = 'failed'
        log_entry['error'] = str(e)
        log_entry['reason'] = 'non_numeric_hourly_rate'
        logger.error(json.dumps(log_entry))
```

## Notes

- **Mistake:** Using `print()` instead of logging in pipelines. Print bypasses handlers and formatters, ruins log aggregation, and is invisible in background jobs.
- **Mistake:** Logging at INFO level for every row in a 10M-row pipeline. Use batch-level logging (rows processed, errors encountered) to avoid log bloat; reserve row-level detail for failures.
- **Connection:** Structured logging integrates naturally with observability tools (Datadog, New Relic) and enables alerting on specific fields (e.g., alert if `status == 'failed'` count > threshold).
- **Revisit:** Exception logging—always log the full traceback with `logger.exception()` in except blocks, not just `str(e)`. This preserves the stack and context needed for debugging.
- **Revisit:** Correlation IDs—in multi-step pipelines, assign each run a unique trace_id and include it in every log entry so you can follow one record through extraction, transformation, and load.
