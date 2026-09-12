---
date: 2026-09-12
phase: python
topic: Logging structured JSON and context propagation
---

# Logging structured JSON and context propagation

*Python for data engineering*

## Concept

Structured JSON logging replaces ad-hoc string formatting with key-value pairs, making logs queryable, parseable, and machine-readable. Instead of `"Processing job 42"`, you emit `{"job_id": 42, "stage": "transform", "duration_ms": 1250}`. Context propagation means threading metadata (request IDs, batch IDs, user context) through function calls so every log line in a call chain includes the same correlation ID—critical when debugging distributed pipelines where a single job triggers reads, transforms, and writes across multiple modules.

Without structured logging, you're regex-parsing text to find failures. Without context propagation, you lose the thread: a crash in an ETL step leaves you guessing which input triggered it, or you manually add context to every function signature. This breaks observability at scale—you can't group related events, filter by user/batch, or measure latency across layers.

In data pipelines, this matters because jobs run asynchronously, process thousands of records in parallel, and fail partially. A malformed salary value may corrupt one row but leave others untouched. Structured logs with context let you correlate that failure to a specific job posting, batch run, and transformation stage in milliseconds.

## Practice

**Problem:** A data pipeline ingests job postings, validates salary_year_avg, and loads into job_postings_fact. Some records have NULL or negative salaries. You need logs that record which job_id failed validation, at what stage, with the bad value—and later queries must correlate all logs for a single batch run.

```sql
-- Use a logs table with structured columns (or VARIANT/JSON in Snowflake/BigQuery)
CREATE TABLE pipeline_logs (
  log_id STRING PRIMARY KEY,
  batch_id STRING,
  job_id INT,
  stage STRING,
  level STRING,
  message STRING,
  salary_value NUMERIC,
  error_code STRING,
  timestamp TIMESTAMP,
  duration_ms INT
);

-- Query all events for a batch:
SELECT stage, level, message, salary_value, duration_ms
FROM pipeline_logs
WHERE batch_id = 'batch_2025_01_15_001'
ORDER BY timestamp;

-- Find all salary validation failures across batches:
SELECT batch_id, job_id, salary_value, message, timestamp
FROM pipeline_logs
WHERE stage = 'validate_salary' AND level = 'ERROR'
ORDER BY timestamp DESC;
```

## Notes

- **Mistake:** Logging only errors. Log stage transitions (start, finish, record count) at INFO level so you can measure latency and spot slow stages even when nothing breaks.
- **Mistake:** Passing context as function arguments instead of using contextvars (Python 3.7+) or thread-local storage; scales poorly and clutters signatures.
- **Connection:** Structured logging pairs with exception handling—catch, log with context and the exception object, then decide to retry or fail-fast. Without context, the exception trace is useless.
- **Adjacent:** Monitoring and alerting consume these logs; set up queries for error rate spikes and SLA violations. Revisit this when adding retry logic—each retry needs a unique attempt_id in the context.
- **Practical tool:** Use `python-json-logger` or `structlog` to emit JSON; wire context via `contextvars.ContextVar` and pass it to loggers, not function parameters.
