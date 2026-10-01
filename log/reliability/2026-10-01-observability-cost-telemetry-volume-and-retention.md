---
date: 2026-10-01
phase: reliability
topic: Observability cost: telemetry volume and retention
---

# Observability cost: telemetry volume and retention

*Quality, reliability and the professional layer*

## Concept

Observability—logs, metrics, traces, and events—scales in cost with volume and retention. A pipeline that emits one event per row processed can generate millions of daily records; keeping all of them indefinitely multiplies storage and query costs. The tension is real: you need enough signal to diagnose failures and understand performance, but not so much that operations become unaffordable or slow.

This matters most when you own the pipeline in production. A prototype that logs everything works fine for weeks; the same approach at scale costs thousands monthly and makes root-cause analysis slower because signal drowns in noise. Without intentional sampling, filtering, and tiered retention (hot/warm/cold storage), you either miss issues or bleed budget.

What breaks: alert fatigue from too much data masks real problems; query performance degrades on enormous log tables; teams disable observability entirely because it's too expensive, leaving them blind to silent failures.

## Practice

**Problem:** The `job_postings_fact` table loads daily with ~50k new rows. Currently, you log every row insertion, transformation step, and validation check—roughly 300k events daily. Storage costs are climbing, and your observability queries are slow. You need to keep detailed logs for 7 days (hot), summarized metrics for 30 days (warm), and delete the rest.

```sql
-- Tiered retention strategy with sampling and summarization

-- 1. Create a lightweight events table with sampling
CREATE TABLE job_postings_events (
  event_id STRING,
  job_id INT,
  event_type STRING,  -- 'row_inserted', 'validation_failed', 'transformation_error'
  severity STRING,    -- 'info', 'warning', 'error'
  message STRING,
  event_timestamp TIMESTAMP,
  _sampled BOOLEAN    -- flag for cost control
);

-- 2. Insert with sampling: log 100% of errors/warnings, 10% of info
INSERT INTO job_postings_events
SELECT
  GENERATE_UUID() AS event_id,
  job_id,
  'row_inserted' AS event_type,
  'info' AS severity,
  CONCAT('Loaded job: ', job_title_short) AS message,
  CURRENT_TIMESTAMP() AS event_timestamp,
  (RAND() < 0.1) AS _sampled  -- 10% sample rate for non-critical events
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE()
  AND (RAND() < 0.1 OR job_salary_year_avg IS NULL);  -- always log nulls

-- 3. Aggregate to metrics table for warm retention (30 days)
CREATE TABLE job_postings_metrics AS
SELECT
  DATE(event_timestamp) AS metric_date,
  event_type,
  severity,
  COUNT(*) AS event_count,
  COUNT(DISTINCT job_id) AS unique_jobs_affected
FROM job_postings_events
WHERE event_timestamp >= CURRENT_TIMESTAMP() - INTERVAL 30 DAY
GROUP BY metric_date, event_type, severity;

-- 4. Retention policy: delete detailed logs older than 7 days
DELETE FROM job_postings_events
WHERE event_timestamp < CURRENT_TIMESTAMP() - INTERVAL 7 DAY;
```

## Notes

- **Sampling bias:** Don't sample errors—log 100% of failures and warnings, sample routine operations. Losing error context is worse than high volume.
- **Cardinality explosion:** Avoid logging high-cardinality fields (job_id, user_id) as separate columns; aggregate them or use tags. One unique value per row defeats compression and indexing.
- **Adjacent: alerting and SLOs.** Observability cost directly impacts which metrics you can afford to track; this constrains what SLOs you can actually monitor.
- **Connecting concept:** log levels and structured logging. Use consistent severity tags (`error`, `warning`, `info`, `debug`) so you can filter cheaply without text parsing.
- **Revisit:** cost optimization by storage tier (S3 for cold logs, Elasticsearch for hot), and cardinality-aware naming conventions to keep metric explosion under control.
