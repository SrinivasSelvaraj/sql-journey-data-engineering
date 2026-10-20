---
date: 2026-10-20
phase: reliability
topic: Resource utilization tracking per workload
---

# Resource utilization tracking per workload

*Quality, reliability and the professional layer*

## Concept

Resource utilization tracking means measuring CPU, memory, I/O, and query execution time *per workload* rather than at the system level. When you own a pipeline, you need to know which jobs consume disproportionate resources, where bottlenecks emerge under load, and whether costs scale linearly with data volume or explode unexpectedly. Without this, you inherit pipelines that "work fine" until they don't—a job that ran in 2 minutes suddenly takes 45, and you have no baseline to detect the anomaly.

The professional layer requires this because resource constraints are often the first friction point between data teams and infrastructure. Being able to say "this job uses 8GB peak memory and 12 CPU-minutes per run" versus "it's slow" determines whether you can negotiate SLAs, predict failure modes, or justify optimization work. It also separates reactive firefighting from proactive capacity planning.

## Practice

**Problem:** You maintain a nightly job that ranks job postings by salary. Recently it's been timing out. You need to log execution metrics (rows processed, duration) for each run so you can spot when behavior degrades and correlate it to data growth.

```sql
CREATE TABLE job_posting_pipeline_metrics (
  run_id STRING,
  job_name STRING,
  execution_date DATE,
  rows_processed INT64,
  execution_time_seconds INT64,
  avg_salary_processed FLOAT64,
  remote_job_pct FLOAT64,
  created_at TIMESTAMP
);

-- Insert after your transformation completes
INSERT INTO job_posting_pipeline_metrics
SELECT
  GENERATE_UUID() as run_id,
  'rank_jobs_by_salary' as job_name,
  CURRENT_DATE() as execution_date,
  COUNT(*) as rows_processed,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), @job_start_time, SECOND) as execution_time_seconds,
  AVG(salary_year_avg) as avg_salary_processed,
  COUNTIF(job_work_from_home) / COUNT(*) as remote_job_pct,
  CURRENT_TIMESTAMP() as created_at
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE();

-- Query to detect degradation
SELECT
  execution_date,
  rows_processed,
  execution_time_seconds,
  ROUND(rows_processed / execution_time_seconds, 2) as rows_per_second,
  LAG(execution_time_seconds) OVER (ORDER BY execution_date) as prev_duration,
  ROUND(((execution_time_seconds - LAG(execution_time_seconds) OVER (ORDER BY execution_date)) 
    / LAG(execution_time_seconds) OVER (ORDER BY execution_date) * 100), 1) as pct_slowdown
FROM job_posting_pipeline_metrics
WHERE job_name = 'rank_jobs_by_salary'
ORDER BY execution_date DESC
LIMIT 30;
```

## Notes

- **Mistake:** Logging only total execution time without row counts. If your dataset grows 3x and time grows 3x, that's healthy—but you won't know without the context.
- **Mistake:** Assuming your dev environment metrics apply to production. Resource contention, data skew, and concurrent jobs change everything; track production-only.
- **Adjacent:** Cost allocation and chargeback models depend entirely on per-workload metrics. Without them, you can't fairly bill teams or justify infrastructure spend.
- **Adjacent:** Alert thresholds should be *relative* (e.g., 20% slower than 7-day rolling average) not absolute, because data grows and queries legitimately take longer.
- **Revisit:** Resource metrics are useless without alerting rules and a postmortem culture. A tracked slowdown you ignore teaches nothing; one that triggers investigation multiplies the value of the log.
