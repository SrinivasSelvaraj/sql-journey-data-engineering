---
date: 2026-09-30
phase: reliability
topic: Tracing: distributed tracing across pipeline components
---

# Tracing: distributed tracing across pipeline components

*Quality, reliability and the professional layer*

## Concept

Distributed tracing follows a single logical request or data transformation as it moves through multiple pipeline components—extracters, transformers, loaders, schedulers—recording timing, errors, and state at each step. Without it, you're left reconstructing failures by grepping logs across a dozen services; with it, you have a single thread connecting cause to effect. In data pipelines specifically, tracing matters when a job completes but produces wrong data (silent failures), when SLAs slip due to bottlenecks you can't locate, or when you inherit a pipeline and need to explain its actual behavior to stakeholders.

The difference between "it ran" and "it ran correctly at the right speed" is observability. A pipeline owner needs to know not just that a transformation took 2 hours, but that 1h 50m was spent waiting for a lock, 9m on a full table scan, and 1m on the actual compute. Without traces, you debug by intuition and hope. With traces, you debug by evidence.

## Practice

**Problem:** A daily job extracts job postings, enriches them with historical salary data, and loads them into `job_postings_fact`. Recently it's been completing in 45 minutes instead of 12, but the row count is correct, so nobody noticed. You need to identify which component degraded and by how much.

```sql
-- Create a trace logging table to instrument each pipeline stage
CREATE TABLE pipeline_traces (
    trace_id STRING,
    stage_name STRING,
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    row_count BIGINT,
    status STRING,
    error_message STRING
);

-- Log extraction stage
INSERT INTO pipeline_traces
SELECT
    'trace_' || date_format(current_timestamp, 'yyyyMMdd_HHmmss') AS trace_id,
    'extract_job_postings' AS stage_name,
    current_timestamp AS start_time,
    NULL,
    COUNT(*),
    'running',
    NULL
FROM job_postings_raw
WHERE job_posted_date = current_date;

-- Log transformation with intermediate row counts
INSERT INTO pipeline_traces
SELECT
    'trace_' || date_format(current_timestamp, 'yyyyMMdd_HHmmss'),
    'enrich_with_salary_history',
    current_timestamp,
    NULL,
    COUNT(*),
    'running',
    NULL
FROM job_postings_raw jp
LEFT JOIN salary_history sh ON jp.job_id = sh.job_id
WHERE jp.job_posted_date = current_date;

-- Query to identify bottleneck
SELECT
    stage_name,
    COUNT(*) as row_count,
    DATEDIFF(MINUTE, start_time, end_time) as duration_minutes,
    ROUND(100.0 * DATEDIFF(MINUTE, start_time, end_time) / 
        SUM(DATEDIFF(MINUTE, start_time, end_time)) OVER (), 1) as pct_total_time
FROM pipeline_traces
WHERE trace_id = (SELECT MAX(trace_id) FROM pipeline_traces)
  AND status IN ('complete', 'running')
GROUP BY stage_name, start_time, end_time
ORDER BY duration_minutes DESC;
```

## Notes

- **Trace IDs must be immutable and unique per run:** Use a timestamp + UUID or job run ID, not incremental counters that break on retries. Propagate it through every log, metric, and error message.

- **Avoid the "log everything" trap:** You'll drown in noise. Trace only stage boundaries, errors, and rows that cross critical thresholds (e.g., when output ≠ input unexpectedly).

- **Connects to:** alerting (use traces to trigger alerts on duration anomalies), lineage tracking (traces answer "which upstream component broke this?"), and cost attribution (traces reveal which stages burn compute).

- **Common mistake:** logging only success. The moment a stage fails silently (0 rows loaded, no error), your trace must flag it. Use `UNION` to capture both success and anomaly paths.

- **Revisit this when:** scaling to parallel tasks (traces must handle fan-out/fan-in), moving to cloud (cloud providers have native tracing—use it), or when blame-shifting becomes common (traces are your neutral arbiter).
