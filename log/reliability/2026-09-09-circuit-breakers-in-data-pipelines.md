---
date: 2026-09-09
phase: reliability
topic: Circuit breakers in data pipelines
---

# Circuit breakers in data pipelines

*Quality, reliability and the professional layer*

## Concept

A circuit breaker is a control mechanism that stops a data pipeline from proceeding when downstream systems are degraded, unavailable, or producing invalid data. Rather than blindly pushing corrupted or redundant data into your warehouse, a circuit breaker detects failure conditions and halts execution—preventing cascading damage and preserving data integrity. This is the difference between "the pipeline ran" and "the pipeline ran *correctly*."

Circuit breakers matter most in production environments where your pipeline feeds business dashboards, ML models, or operational systems. Without them, a failing API can corrupt months of data before anyone notices; a schema change upstream goes undetected; a malformed batch silently overwrites good records. The cost of detection weeks later—manual cleanup, lost trust, retracted insights—far exceeds the cost of failing fast.

Implementation requires three things: (1) a health check or validation gate before the write, (2) a clear failure threshold (e.g., "stop if >5% of rows fail validation"), and (3) an alert that wakes someone up. The circuit "trips" and the pipeline stops. This is *good*. It forces you to investigate and fix the root cause rather than letting bad data compound.

## Practice

**Problem:** Your `job_postings_fact` table is being loaded nightly from an external API. Recently, the API started returning NULL values for `salary_year_avg` on 30% of records (a schema change on their end). Your current pipeline has no guardrails—it loads everything. You need a circuit breaker that validates data quality *before* the insert, and stops if the null rate exceeds a threshold.

```sql
-- Circuit breaker validation logic (run before INSERT)
WITH validation AS (
  SELECT
    COUNT(*) AS total_rows,
    COUNTIF(salary_year_avg IS NULL) AS null_salary_count,
    COUNTIF(salary_year_avg IS NULL) / COUNT(*) AS null_rate
  FROM staging.job_postings_raw
)
SELECT
  CASE
    WHEN null_rate > 0.10 THEN 'CIRCUIT_OPEN'
    WHEN total_rows = 0 THEN 'CIRCUIT_OPEN'
    ELSE 'CIRCUIT_CLOSED'
  END AS circuit_status,
  null_rate,
  total_rows,
  null_salary_count
FROM validation;

-- Only proceed with INSERT if circuit is CLOSED
-- Pseudocode for orchestration layer:
-- IF circuit_status = 'CIRCUIT_OPEN' THEN
--   RAISE ALERT to data-eng@company.com
--   STOP PIPELINE
-- ELSE
--   INSERT INTO job_postings_fact SELECT ...
```

## Notes

- **Common mistake:** Setting thresholds too loose (e.g., "fail if 50% is null") defeats the purpose. A 10–15% anomaly in a usually-clean source is worth investigating. Calibrate thresholds to *your* baseline, not industry defaults.

- **Related concept — dead letter queues:** Circuit breakers stop the pipeline; DLQs capture the bad records for later inspection. Use both: stop the write, but keep the evidence.

- **Observability prerequisite:** A circuit breaker only works if you *know* when it trips. Wire alerts to Slack, PagerDuty, or your incident system. A silently tripped breaker is useless.

- **Testing the breaker:** Deliberately inject bad data in staging to verify the circuit actually opens and alerts fire. If you've never tested it, you haven't shipped it.

- **Adjacent topic — idempotency:** Once a circuit trips, your orchestration may retry. Design your pipeline to be idempotent so a retry after fix doesn't duplicate rows.
