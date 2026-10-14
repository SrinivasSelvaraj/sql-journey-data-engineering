---
date: 2026-10-14
phase: pipelines
topic: Checkpoint and savepoint: resuming from failure point
---

# Checkpoint and savepoint: resuming from failure point

*Pipelines and orchestration*

## Concept

A **checkpoint** is a persistent marker of successful completion at a discrete stage in a data pipeline, while a **savepoint** is an intermediate state snapshot that allows resumption without reprocessing. Together, they enable pipelines to recover from failure by skipping already-completed work and resuming from the last known good state, rather than rerunning the entire job.

Without checkpoints, a 12-hour pipeline that fails at hour 11 must restart from scratch. Without savepoints, you lose intermediate computations (transformed tables, aggregated datasets, filtered views) and must rebuild them. This becomes critical when pipelines are expensive (large scans, external API calls), frequent (hourly ingests), or dependent on temporal windows (daily batch jobs that must complete within a maintenance window).

In practice: checkpoints are metadata (a row in a control table, a file marker, a database transaction log), while savepoints are data artifacts (intermediate tables, Parquet checkpoint files, state stores). Modern orchestrators like Airflow use task status as checkpoints; Spark uses write-ahead logs; dbt uses manifest state. The pattern fails when checkpoint logic ignores idempotency, when savepoints aren't version-controlled, or when retry logic doesn't preserve data lineage.

## Practice

**Problem:** A daily job loads job postings, enriches them with salary statistics by title, and flags remote-eligible roles. It crashes after 6 hours (during the enrichment join) due to a memory spike. Without checkpoints, the next run re-ingests and re-aggregates 2 million postings. With checkpoints, it should skip loading and resume enrichment.

```sql
-- Control table: tracks job stage completion
CREATE TABLE IF NOT EXISTS pipeline_checkpoint (
  pipeline_name VARCHAR,
  stage_name VARCHAR,
  checkpoint_id INT,
  completed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  record_count INT,
  PRIMARY KEY (pipeline_name, stage_name)
);

-- Savepoint: intermediate result from stage 1 (load & deduplicate)
CREATE TABLE job_postings_loaded AS
SELECT DISTINCT 
  job_id, job_title_short, salary_year_avg, 
  job_work_from_home, job_posted_date, job_location
FROM raw_job_postings
WHERE job_posted_date = CURRENT_DATE;

INSERT INTO pipeline_checkpoint 
VALUES ('daily_job_enrichment', 'load', 1, CURRENT_TIMESTAMP, (SELECT COUNT(*) FROM job_postings_loaded));

-- Savepoint: intermediate result from stage 2 (aggregate salary stats)
CREATE TABLE salary_stats_by_title AS
SELECT 
  job_title_short,
  AVG(salary_year_avg) AS avg_salary,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary_year_avg) AS p75_salary,
  COUNT(*) AS title_count
FROM job_postings_loaded
GROUP BY job_title_short;

INSERT INTO pipeline_checkpoint 
VALUES ('daily_job_enrichment', 'aggregate', 2, CURRENT_TIMESTAMP, (SELECT COUNT(*) FROM salary_stats_by_title));

-- Stage 3: resume here on retry (uses savepoints from stages 1–2)
CREATE TABLE job_postings_fact AS
SELECT 
  jp.job_id, jp.job_title_short, jp.salary_year_avg,
  jp.job_work_from_home, jp.job_posted_date, jp.job_location,
  ss.avg_salary, ss.p75_salary,
  CASE WHEN jp.job_work_from_home THEN 1 ELSE 0 END AS is_remote
FROM job_postings_loaded jp
LEFT JOIN salary_stats_by_title ss ON jp.job_title_short = ss.job_title_short;

INSERT INTO pipeline_checkpoint 
VALUES ('daily_job_enrichment', 'enrich', 3, CURRENT_TIMESTAMP, (SELECT COUNT(*) FROM job_postings_fact));

-- Query to check last successful stage (for conditional retry logic)
SELECT stage_name, completed_at FROM pipeline_checkpoint 
WHERE pipeline_name = 'daily_job_enrichment' 
ORDER BY checkpoint_id DESC LIMIT 1;
```

## Notes

- **Idempotency trap:** savepoints are only safe to reuse if source data hasn't changed between failure and retry. Use date partitioning and `MERGE` instead of `INSERT` to handle reruns of the same logical day.
- **Checkpoint granularity:** too many checkpoints add overhead (metadata bloat); too few defeat recovery. Checkpoint after expensive operations (joins, aggregations, external calls) and before risky ones.
- **Version control for savepoints:** treat intermediate tables like code; tag them with pipeline run_id or date_partition so old versions don't interfere with reruns. Drop stale savepoints explicitly.
- **Adjacent topics:** task idempotency (same input → same output), data lineage tracking (knowing which savepoint fed which output), and eventual consistency (acceptable lag between stages during partial failures).
- **Orchestrator patterns:**
