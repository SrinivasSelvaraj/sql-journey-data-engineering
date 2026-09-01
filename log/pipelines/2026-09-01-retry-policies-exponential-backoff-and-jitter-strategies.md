---
date: 2026-09-01
phase: pipelines
topic: Retry policies: exponential backoff and jitter strategies
---

# Retry policies: exponential backoff and jitter strategies

*Pipelines and orchestration*

## Concept

Retry policies with exponential backoff and jitter prevent cascading failures when transient errors occur in data pipelines. Instead of retrying immediately (which hammers a temporarily overloaded service), exponential backoff increases the delay between attempts: 1s, 2s, 4s, 8s. Jitter randomizes these intervals slightly so that multiple failed workers don't retry in synchronized waves, overwhelming the service a second time.

This matters most when calling external APIs, writing to databases under load, or orchestrating distributed tasks. Without retry logic, a 5-second network blip crashes your pipeline. Without backoff, you make it worse. Without jitter, you create the thundering herd problem where 100 workers all retry at second 8, causing another cascade.

Properly configured retries let transient failures self-heal; the pipeline pauses, the service recovers, and work resumes. They turn flaky infrastructure into reliable systems without code changes upstream.

## Practice

**Problem:** A job posting ingestion pipeline calls an external API to enrich salary data. The API is rate-limited and occasionally returns 429 (too many requests) or 503 (service unavailable). You need to retry failed enrichment requests before marking records as permanently failed.

```sql
-- Orchestration layer (pseudo-code in dbt or Airflow operator)
-- Implement retry with exponential backoff + jitter in your calling code:

WITH max_retries AS (
  SELECT 3 AS max_attempts,
         1.0 AS base_delay_seconds
),
enrichment_attempts AS (
  SELECT 
    job_id,
    job_title_short,
    job_location,
    attempt_number,
    CASE 
      WHEN attempt_number = 1 THEN 0
      WHEN attempt_number = 2 THEN base_delay_seconds * POW(2, attempt_number - 2) + RAND() * 0.5
      WHEN attempt_number = 3 THEN base_delay_seconds * POW(2, attempt_number - 2) + RAND() * 1.0
    END AS delay_seconds,
    CASE 
      WHEN http_status = 200 THEN 'success'
      WHEN http_status IN (429, 503) AND attempt_number < 3 THEN 'retry'
      ELSE 'failed'
    END AS status
  FROM job_postings_raw
  CROSS JOIN (SELECT * FROM max_retries)
  LEFT JOIN external_api_responses USING (job_id)
)
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  status,
  attempt_number,
  delay_seconds
FROM enrichment_attempts
WHERE status = 'success' 
   OR (status = 'retry' AND delay_seconds IS NOT NULL);
```

**In practice:** configure your orchestrator (Airflow, dbt Cloud, Prefect) to retry tasks with `max_retries=3` and `retry_delay=exponential_backoff(base=1)`, plus a jitter factor. Log attempt metadata to troubleshoot.

## Notes

- **Common mistake:** retrying with fixed delays or no jitter causes synchronized retries across parallel workers—defeats the purpose. Always add randomization.
- **Deadletter pattern:** after max retries, route failed records to a quarantine table with full context (attempt count, error message, timestamp) for manual investigation, not silent drop.
- **Distinguishing transient vs. permanent:** only retry on 429, 503, timeout, connection reset. Don't retry 400 (bad request) or 401 (auth)—those won't fix themselves.
- **Adjacent: circuit breaker pattern:** if a service fails repeatedly, stop sending requests for a cooldown period rather than hammering it. Pairs naturally with backoff.
- **Revisit:** monitor retry rates and backoff durations in production; if >10% of requests need retries, investigate the root cause (capacity, dependency degradation) rather than tuning delays indefinitely.
