---
date: 2026-10-19
phase: reliability
topic: OpenTelemetry instrumentation and trace sampling
---

# OpenTelemetry instrumentation and trace sampling

*Quality, reliability and the professional layer*

## Concept

OpenTelemetry (OTel) instrumentation is the practice of embedding observability hooks into your data pipelines so that every operation—extraction, transformation, load—emits structured trace data showing what happened, how long it took, and where failures occurred. Without it, you're flying blind: a pipeline that silently drops 10% of records, transforms data incorrectly downstream, or hangs for 20 minutes has no audit trail and no way to debug in production.

Trace sampling is the mechanism that makes this sustainable at scale. You cannot afford to emit a complete trace for every single row in a billion-row dataset; instead, you sample—perhaps 1 in 1000 events—and configure that sampling intelligently so that errors and outliers are *always* captured while normal execution is sampled down. This is the professional layer: knowing *what* to observe, *when* to sample aggressively, and *how* to correlate partial traces back to root cause.

This matters because production data pipelines fail silently and frequently. A schema drift, a network timeout, a resource exhaustion—these don't always surface as loud exceptions. Instrumentation with thoughtful sampling lets you detect anomalies (latency spikes, error rate increases) and reconstruct what went wrong without drowning in terabytes of trace data.

## Practice

**Problem:** Your job postings pipeline runs daily, ingesting 50,000 records. Last week, you noticed salary_year_avg values were suddenly NULL for 15% of records, but the pipeline exited cleanly with no errors. You need to add instrumentation to catch data quality regressions earlier, and sample traces so you capture salary nulls and slow transformations without logging every single record.

```sql
-- Add observability columns and trace metadata to your pipeline
-- Assume this is a dbt model or transformation step

WITH instrumented_source AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    -- Trace context
    CURRENT_TIMESTAMP() AS trace_timestamp,
    GENERATE_UUID() AS trace_id,
    -- Sampling decision: always capture nulls, otherwise 1%
    CASE 
      WHEN salary_year_avg IS NULL THEN TRUE
      ELSE RAND() < 0.01
    END AS should_trace,
    -- Data quality signals
    CASE WHEN salary_year_avg IS NULL THEN 'salary_null' ELSE 'ok' END AS data_quality_flag
  FROM raw_job_postings
),
traced_and_filtered AS (
  SELECT * FROM instrumented_source
  WHERE should_trace OR data_quality_flag != 'ok'
)
-- Write traced records to observability sink (e.g., Cloud Logging, Datadog)
-- SELECT * FROM traced_and_filtered;

-- Main job_postings_fact table (all records, instrumented job_id)
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM instrumented_source
WHERE should_trace = FALSE OR data_quality_flag != 'ok'
```

## Notes

- **Common mistake:** Sampling uniformly by record ID rather than by anomaly. You will miss the 15% of records with NULL salary because they're rare. Always bias sampling toward errors, nulls, and statistical outliers.
- **Adjacent topics:** Data quality monitoring (Great Expectations, dbt tests) works *with* tracing, not instead of it. Tests tell you *that* something broke; traces tell you *why* and *when*.
- **Correlation ID pattern:** Use a trace_id that propagates through every step (extraction → staging → fact table). When a downstream query fails, you can trace backward to the exact source record and transformation step that caused it.
- **Revisit:** The tension between comprehensive observability and operational cost. Start with error-biased sampling, then gradually reduce the threshold as your monitoring matures and you understand what signals matter.
- **Tool integration:** OTel exporters (Jaeger, Honeycomb, Datadog) consume these traces. Hook your pipeline's logging to OTel SDKs so traces appear in the same system where you're already looking for incidents.
