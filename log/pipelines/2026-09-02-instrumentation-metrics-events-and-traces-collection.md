---
date: 2026-09-02
phase: pipelines
topic: Instrumentation: metrics, events and traces collection
---

# Instrumentation: metrics, events and traces collection

*Pipelines and orchestration*

## Concept

Instrumentation—collecting metrics, events, and traces—turns invisible pipelines into observable systems. Metrics track aggregate health (row counts, latency, freshness), events log discrete occurrences (job posting ingested, salary validation failed), and traces follow data flow through stages. Without instrumentation, failures hide: a job posting pipeline silently drops 10% of records, stale salary data goes unnoticed, and you debug by reading logs instead of dashboards.

In orchestration, instrumentation serves three purposes: *fail loudly* by alerting on anomalies before they compound, *rerun safely* by tracking which records succeeded so retries don't duplicate, and *explain themselves* by letting you trace why a specific job posting is missing or incorrect. A job posting may fail validation, get retried, succeed partially, or arrive late—instrumentation records each state transition.

Without it, you're flying blind. A scheduling system doesn't know if 100 jobs arrived or 10,000. A data warehouse accepts silently corrupt salary figures. Rerun logic can't distinguish between "never processed" and "failed mid-way," causing duplicate or lost records.

## Practice

**Problem:** Your `job_postings_fact` ingestion pipeline runs daily. You need to detect:
- Freshness: when no new postings arrive for 24+ hours
- Quality: when salary data is null for >5% of records
- Idempotency: whether a rerun will duplicate rows or safely skip already-processed job_ids

**Solution:**

```sql
-- Create instrumentation tables
CREATE TABLE pipeline_metrics (
  pipeline_run_id STRING,
  metric_name STRING,
  metric_value FLOAT,
  measure_time TIMESTAMP,
  PRIMARY KEY (pipeline_run_id, metric_name)
);

CREATE TABLE pipeline_events (
  event_id STRING PRIMARY KEY,
  pipeline_run_id STRING,
  event_type STRING, -- 'ingestion_start', 'validation_failed', 'row_processed', 'rerun'
  job_id STRING,
  event_details MAP<STRING, STRING>,
  event_time TIMESTAMP
);

-- At pipeline start
INSERT INTO pipeline_metrics
SELECT 
  '{{run_id}}' as pipeline_run_id,
  'freshness_hours' as metric_name,
  DATEDIFF(HOUR, MAX(job_posted_date), CURRENT_TIMESTAMP) as metric_value,
  CURRENT_TIMESTAMP as measure_time
FROM job_postings_fact;

-- During ingestion, log each row's outcome
INSERT INTO pipeline_events
SELECT 
  CONCAT('{{run_id}}_', job_id, '_', ROW_NUMBER() OVER (ORDER BY job_id)) as event_id,
  '{{run_id}}' as pipeline_run_id,
  CASE 
    WHEN salary_year_avg IS NULL THEN 'validation_failed'
    WHEN job_id IN (SELECT job_id FROM job_postings_fact WHERE job_posted_date < CURRENT_DATE) 
      THEN 'duplicate_detected'
    ELSE 'row_processed' 
  END as event_type,
  job_id,
  MAP('title', job_title_short, 'salary', CAST(salary_year_avg AS STRING)) as event_details,
  CURRENT_TIMESTAMP as event_time
FROM staging_job_postings;

-- Quality check: alert if salary nulls exceed threshold
INSERT INTO pipeline_metrics
SELECT 
  '{{run_id}}' as pipeline_run_id,
  'null_salary_percent' as metric_name,
  (COUNTIF(salary_year_avg IS NULL) / COUNT(*)) * 100.0 as metric_value,
  CURRENT_TIMESTAMP as measure_time
FROM staging_job_postings;

-- Idempotency: mark which job_ids are safe to load
INSERT INTO pipeline_events
SELECT 
  CONCAT('{{run_id}}_idempotent_check_', job_id) as event_id,
  '{{run_id}}' as pipeline_run_id,
  'rerun_safe' as event_type,
  job_id,
  MAP('already_loaded', CASE WHEN jf.job_id IS NOT NULL THEN 'true' ELSE 'false' END) as event_details,
  CURRENT_TIMESTAMP as event_time
FROM staging_job_postings s
LEFT JOIN job_postings_fact jf ON s.job_id = jf.job_id AND s.job_posted_date = jf.job_posted_date;
```

## Notes

- **Anti-pattern:** Logging everything without cardinality limits. If job_id is unbounded, storing every `row_processed` event explodes storage. Instead, sample or aggregate: log 1-in-100 successes, all failures.
- **Cardinality awareness:** Metrics (aggregate counts, latencies) are bounded and cheap; events (per-row details) can explode. Use events only for failures, anomalies, and state transitions that need
