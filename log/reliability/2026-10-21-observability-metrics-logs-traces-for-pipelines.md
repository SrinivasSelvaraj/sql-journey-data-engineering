---
date: 2026-10-21
phase: reliability
topic: Observability: metrics, logs, traces for pipelines
---

# Observability: metrics, logs, traces for pipelines

*Quality, reliability and the professional layer*

## Concept

Observability in data pipelines means instrumenting your system with metrics, logs, and traces so you can understand what happened, why it failed, and where time is spent—without needing to query production data or re-run jobs. Metrics are aggregated counts (rows processed, latency, error rate); logs are timestamped events with context (which file failed, what transformation errored); traces are causal chains showing how data moves through stages. This matters because pipelines fail silently: a job can complete with wrong data, late arrivals, or skipped records. Without observability, you discover problems from downstream complaints, not proactively. With it, you detect data quality drift, schema breaks, and performance degradation before stakeholders notice.

The difference between owning a pipeline and building one is confidence under pressure. An owner can answer "why did yesterday's load have 15% fewer rows?" in minutes using logs and metrics, not hours of debugging. They set alerting thresholds aligned to SLAs. They can correlate a schema change upstream with a downstream latency spike using traces. Without observability, you're reactive; with it, you're predictive and forensically capable.

## Practice

**Problem:** The `job_postings_fact` table is loaded nightly. Recently, some loads complete in 5 minutes, others in 45 minutes. Stakeholders report salary data sometimes arrives incomplete. You need to detect when loading degrades and why.

```sql
-- Add observability layer: metrics, logs, and data quality checks

-- METRICS: Log job execution stats
CREATE TABLE IF NOT EXISTS pipeline_metrics (
  pipeline_name STRING,
  run_id STRING,
  stage_name STRING,
  metric_name STRING,
  metric_value DECIMAL(18,2),
  recorded_at TIMESTAMP,
  duration_seconds INT
);

INSERT INTO pipeline_metrics
SELECT 
  'job_postings_load' as pipeline_name,
  '{{run_id}}' as run_id,
  'extract' as stage_name,
  'row_count' as metric_name,
  COUNT(*) as metric_value,
  CURRENT_TIMESTAMP as recorded_at,
  {{extract_duration_seconds}} as duration_seconds
FROM job_postings_raw;

-- LOGS: Structured event log for debugging
CREATE TABLE IF NOT EXISTS pipeline_logs (
  log_id STRING,
  pipeline_name STRING,
  run_id STRING,
  log_level STRING,
  message STRING,
  context MAP<STRING, STRING>,
  logged_at TIMESTAMP
);

INSERT INTO pipeline_logs
VALUES (
  '{{uuid()}}',
  'job_postings_load',
  '{{run_id}}',
  'INFO',
  'Transform complete: salary nulls detected',
  MAP('null_count', '{{null_salary_count}}', 'total_rows', '{{total_rows}}'),
  CURRENT_TIMESTAMP
);

-- DATA QUALITY CHECKS: Prevent bad data from reaching fact table
CREATE TABLE IF NOT EXISTS job_postings_fact AS
SELECT 
  job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM job_postings_transformed
WHERE 
  job_id IS NOT NULL
  AND job_posted_date <= CURRENT_DATE
  AND salary_year_avg > 0 OR salary_year_avg IS NULL; -- Allow nulls, reject invalid values

-- ALERT: Query metrics to detect anomalies
SELECT 
  run_id,
  SUM(CASE WHEN metric_name = 'row_count' THEN metric_value ELSE 0 END) as rows_loaded,
  MAX(CASE WHEN metric_name = 'salary_null_pct' THEN metric_value ELSE 0 END) as salary_null_pct,
  MAX(duration_seconds) as load_duration_sec,
  CASE 
    WHEN MAX(duration_seconds) > 1800 THEN 'WARN: slow load'
    WHEN MAX(CASE WHEN metric_name = 'salary_null_pct' THEN metric_value ELSE 0 END) > 0.05 THEN 'WARN: high null rate'
    ELSE 'OK'
  END as alert_status
FROM pipeline_metrics
WHERE pipeline_name = 'job_postings_load'
  AND recorded_at >= CURRENT_TIMESTAMP - INTERVAL 24 HOUR
GROUP BY run_id;
```

## Notes

- **Mistake:** Logging everything but querying nothing. Set up dashboards and alert rules immediately; metrics without action are noise.
- **Mistake:** Treating logs and metrics as separate concerns. Correlate them—when latency spikes, find which stage logged errors at that time using `recorded_at` and `run_id`.
- **Adjacent topic:** Data lineage and impact analysis (knowing which downstream tables depend on this one so you know who to notify when quality breaks).
- **Adjacent topic:** SLI/SLO definition (e.g., 99% of loads complete in
