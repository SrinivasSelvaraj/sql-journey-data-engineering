---
date: 2026-10-13
phase: pipelines
topic: Backpressure handling: downstream system overload
---

# Backpressure handling: downstream system overload

*Pipelines and orchestration*

## Concept

Backpressure handling is the mechanism that prevents a data pipeline from overwhelming downstream systems (databases, APIs, message queues) by producing data faster than it can be consumed. Without it, you risk timeouts, connection pool exhaustion, OOM errors, or silent data loss when queues drop overflow. Backpressure manifests as either *buffering* (holding data in memory or on disk until the sink catches up) or *throttling* (deliberately slowing the source to match the sink's capacity).

In practice, backpressure matters most when your pipeline ingests from high-volume sources (APIs with rate limits, Kafka topics, CDC streams) or writes to shared infrastructure (data warehouses during ETL windows, shared Postgres instances). A pipeline that ignores backpressure will appear to succeed while actually losing data or corrupting state.

The solution requires three layers: *detection* (monitor sink latency, queue depth, or explicit error codes), *propagation* (surface signals back to the source), and *response* (pause, batch smaller, or fail loudly). Orchestration tools like Airflow, dbt, or custom retry logic must implement these explicitly—they do not happen by default.

## Practice

**Problem:** A job posting ingestion pipeline reads from an API that returns 10k records/sec, but your Postgres warehouse can only sustain ~500 inserts/sec during business hours due to concurrent reporting queries. Records are being silently dropped or duplicated.

**Solution:**

```sql
-- Detect backpressure: monitor sink lag
CREATE TABLE pipeline_sink_metrics AS
SELECT 
  CURRENT_TIMESTAMP as checked_at,
  COUNT(*) as pending_rows,
  MAX(job_posted_date) as max_ingested_date,
  EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MAX(job_posted_date))) as lag_seconds
FROM job_postings_fact
WHERE job_posted_date > CURRENT_TIMESTAMP - INTERVAL '1 hour'
  AND _loaded_at IS NULL;  -- unflushed rows

-- Implement response: batch writes with explicit sizing and circuit breaker
WITH staged_batch AS (
  SELECT 
    job_id, job_title_short, salary_year_avg, job_work_from_home, 
    job_posted_date, job_location,
    ROW_NUMBER() OVER (ORDER BY job_posted_date) as batch_seq
  FROM job_postings_staging
  WHERE processed = FALSE
  LIMIT 100  -- reduced from 10k; tune based on sink metrics
)
INSERT INTO job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location, _loaded_at)
SELECT 
  job_id, job_title_short, salary_year_avg, job_work_from_home, 
  job_posted_date, job_location, CURRENT_TIMESTAMP
FROM staged_batch
ON CONFLICT (job_id) DO NOTHING;  -- prevent duplicates under retry

-- Fail loudly if backpressure threshold exceeded
DO $$
DECLARE
  lag_seconds INT;
BEGIN
  SELECT EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MAX(job_posted_date)))::INT
    INTO lag_seconds
  FROM job_postings_fact
  WHERE job_posted_date > CURRENT_TIMESTAMP - INTERVAL '1 hour'
    AND _loaded_at IS NULL;
  
  IF lag_seconds > 300 THEN  -- 5 min threshold
    RAISE EXCEPTION 'Sink lag exceeds 300s (actual: % s). Halting ingestion.', lag_seconds;
  END IF;
END $$;
```

## Notes

- **Confusing buffering with throughput:** Buffering masks backpressure; it delays the problem rather than solving it. Always monitor end-to-end latency, not just queue depth.
- **Hardcoding batch sizes:** Batch sizes must be dynamic, tied to measured sink latency and connection pool availability. A fixed `LIMIT 1000` works until it doesn't (e.g., during maintenance windows).
- **Missing idempotency keys:** Backpressure handling requires safe retries. Without unique constraints or deduplication logic (`ON CONFLICT`), retried batches create duplicates.
- **Adjacent: Dead-letter queues and circuit breakers.** Route failed batches to a DLQ and implement exponential backoff or circuit-breaker patterns (e.g., stop writing if 3 consecutive batches fail).
- **Revisit: Monitoring pipeline SLOs.** Backpressure handling is observable only if you track latency SLOs (e.g., "95th percentile end-to-end latency < 5 min") and alert on violations before data loss occurs.
