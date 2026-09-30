---
date: 2026-09-30
phase: reliability
topic: Observability: logs, metrics and traces for pipelines
---

# Observability: logs, metrics and traces for pipelines

*Quality, reliability and the professional layer*

## Concept

Observability is the ability to understand what your pipeline is doing *while it runs*, not just whether it succeeded or failed. It's built on three pillars: **logs** (discrete events and decisions), **metrics** (quantified measurements over time), and **traces** (request/task flow across systems). Without it, you inherit silent failures—a pipeline that completes but loads 10% fewer rows than yesterday, or transforms salaries incorrectly in a way that only surfaces in dashboards weeks later.

Most junior engineers build pipelines that work once. Owning a pipeline means answering: How many records were rejected and why? What's the 95th percentile latency? Did upstream schema changes break my transforms? These questions are unanswerable without instrumentation baked in from the start. A pipeline without observability is a black box that only reveals problems after users complain.

The cost of poor observability compounds: debugging production incidents becomes guesswork, SLAs slip, and trust erodes. The difference between "it ran" and "I know what it did" is professionalism.

## Practice

**Problem:** Your `job_postings_fact` pipeline runs daily but you suspect data quality issues. You need to detect:
- Records with NULL salary_year_avg when they shouldn't be
- Job postings with impossible dates (posted in the future)
- A sudden drop in remote work jobs (job_work_from_home = TRUE)

**Solution:**

```sql
-- Observability queries: run these after your load, log or alert on thresholds
WITH quality_checks AS (
  SELECT
    CURRENT_TIMESTAMP as check_timestamp,
    COUNT(*) as total_records,
    COUNTIF(salary_year_avg IS NULL) as null_salaries,
    COUNTIF(job_posted_date > CURRENT_DATE()) as future_dates,
    COUNTIF(job_work_from_home = TRUE) as remote_jobs,
    COUNTIF(job_work_from_home = TRUE) / COUNT(*) as pct_remote
  FROM job_postings_fact
  WHERE job_posted_date = CURRENT_DATE() - 1
)
SELECT
  *,
  CASE 
    WHEN null_salaries > total_records * 0.05 THEN 'ALERT: High NULL salary rate'
    WHEN future_dates > 0 THEN 'ALERT: Invalid future dates detected'
    WHEN pct_remote < 0.15 THEN 'ALERT: Remote job % dropped below baseline'
    ELSE 'OK'
  END as data_quality_status
FROM quality_checks;

-- Log this to a metrics table for trend tracking
INSERT INTO pipeline_metrics (pipeline_name, metric_name, metric_value, recorded_at)
SELECT
  'job_postings_daily',
  'null_salary_count',
  null_salaries,
  CURRENT_TIMESTAMP
FROM quality_checks;
```

## Notes

- **Mistake:** Treating observability as optional or "nice-to-have." Add it during the initial build, not as an afterthought. It's cheaper to instrument early.
- **Adjacent:** Data quality frameworks (Great Expectations, dbt tests) are part of observability but focus narrowly on schema/value validation. Observability is broader—it includes performance, throughput, and business logic anomalies.
- **Mistake:** Only logging errors. Log normal operations at key checkpoints (rows in, rows out, transformations applied). You need baseline behavior to detect drift.
- **Reconnect to:** SLOs/SLIs (service level objectives/indicators) and alerting strategies. Metrics without thresholds and runbooks are noise.
- **Worth revisiting:** The tradeoff between log verbosity and cost. Structured logging (JSON) and sampling strategies become critical at scale.
