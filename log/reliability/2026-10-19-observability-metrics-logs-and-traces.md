---
date: 2026-10-19
phase: reliability
topic: Observability: metrics, logs and traces
---

# Observability: metrics, logs and traces

*Quality, reliability and the professional layer*

## Concept

Observability is the ability to understand what your data pipeline is doing by examining its outputs—metrics, logs, and traces. Unlike monitoring (which tells you *if* something is wrong), observability tells you *why*. Metrics answer "how much" (row counts, latency, freshness), logs answer "what happened" (transformation details, errors, data quality issues), and traces answer "how did we get here" (lineage through the pipeline, timing at each step).

This matters most when you own a pipeline in production. A pipeline that works once is not the same as one you can trust to run nightly and alert you intelligently when something subtle breaks—like salary data suddenly dropping 30% because a source schema changed, or job postings appearing 3 days late because an upstream API throttled. Without observability, you discover problems from angry stakeholders, not from your own instrumentation.

Without it, you're flying blind. You might rebuild the same table three times debugging a logic error that logs would have shown in seconds. You can't distinguish between "the pipeline failed" and "the pipeline succeeded but the data is wrong," which is the difference between a page at 2am and a quiet production issue that silently corrupts your fact table.

## Practice

**Problem**: You load `job_postings_fact` nightly from a source API. Lately, the business notices that average salary (`salary_year_avg`) has dropped significantly, and you don't know if it's real data drift, a parsing error, a schema change, or a filtering bug. You need to detect this automatically.

```sql
-- Create metrics table to track health over time
CREATE TABLE IF NOT EXISTS job_postings_metrics (
  metric_date DATE,
  row_count BIGINT,
  salary_avg DECIMAL(10,2),
  salary_min DECIMAL(10,2),
  salary_max DECIMAL(10,2),
  null_salary_count BIGINT,
  remote_pct DECIMAL(5,2),
  days_since_posted_avg INT,
  loaded_at TIMESTAMP
);

-- Insert after each load
INSERT INTO job_postings_metrics
SELECT
  CAST(CURRENT_DATE AS DATE),
  COUNT(*),
  AVG(salary_year_avg),
  MIN(salary_year_avg),
  MAX(salary_year_avg),
  COUNT(*) FILTER (WHERE salary_year_avg IS NULL),
  ROUND(100.0 * SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) / COUNT(*), 2),
  AVG(CAST(CURRENT_DATE - job_posted_date AS INT)),
  CURRENT_TIMESTAMP
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days';

-- Alert query: detect anomalies
SELECT
  metric_date,
  row_count,
  salary_avg,
  LAG(salary_avg) OVER (ORDER BY metric_date) AS prev_salary_avg,
  ROUND(100.0 * (salary_avg - LAG(salary_avg) OVER (ORDER BY metric_date)) 
    / LAG(salary_avg) OVER (ORDER BY metric_date), 2) AS pct_change
FROM job_postings_metrics
WHERE metric_date >= CURRENT_DATE - 7
  AND ABS(ROUND(100.0 * (salary_avg - LAG(salary_avg) OVER (ORDER BY metric_date)) 
    / LAG(salary_avg) OVER (ORDER BY metric_date), 2)) > 10;
```

## Notes

- **Mistake**: Metrics only. Logs and traces are just as critical. A sudden drop in salary might come from a parsing error (log it), a source API schema change (trace the lineage), or real data drift (metric tells you it happened, logs tell you why).

- **Mistake**: Alerting on the wrong threshold. A 5% day-to-day variance in average salary is noise; 30% is signal. Baseline your thresholds on actual variance in your domain, not arbitrary numbers.

- **Connection to**: Data lineage and impact analysis. Observability without understanding *which upstream source* caused a change is half-useful. Combine metrics with source tags so you can trace problems backward.

- **Revisit**: The difference between *in-pipeline* instrumentation (logs emitted during transformation) and *post-pipeline* metrics (computed on the final table). Both matter; the first is faster for debugging, the second is what stakeholders care about.

- **Ownership signal**: Someone who "builds pipelines" runs one manually and checks the result. Someone who *owns* them writes the metrics query first, defines what "healthy" looks like, and sleeps soundly knowing they'll be woken only by real problems.
