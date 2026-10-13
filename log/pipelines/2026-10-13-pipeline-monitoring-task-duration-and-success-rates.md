---
date: 2026-10-13
phase: pipelines
topic: Pipeline monitoring: task duration and success rates
---

# Pipeline monitoring: task duration and success rates

*Pipelines and orchestration*

## Concept

Pipeline monitoring at the task level means systematically tracking how long each step takes to execute and whether it succeeds or fails. This is critical because a pipeline can appear to "succeed" overall while individual tasks degrade silently—a slow data quality check, a suddenly-failing API call, or a memory leak in a transformation. Without visibility into task-level metrics, you won't know *where* to look when latency increases or quality drops.

Task duration tracking reveals performance regressions before they cascade downstream. If your job posting ingestion task typically runs in 2 minutes but suddenly takes 12, that's a signal to investigate schema changes, data volume spikes, or resource contention. Success rates (pass/fail counts per task, not just per pipeline run) let you catch intermittent failures that might otherwise hide behind retry logic. A task that fails 1 in 50 times will eventually break production—you need to spot that pattern in logs, not discover it in a p1 incident.

Monitoring without actionability is just noise. Log task start time, end time, row counts processed, and error messages in a structured way so you can query them later. Store these metrics in a table or time-series database, not just console output. Then alert on meaningful thresholds: duration exceeding 3 standard deviations from the mean, or failure rate exceeding 2% in the last 24 hours.

## Practice

**Problem:** Your job postings pipeline runs daily. The main fact table load completes, but you notice some days the downstream reporting is incomplete. You suspect the ingestion task sometimes fails silently or a transformation step is dropping rows without warning. Design a monitoring query to flag tasks that have unusual duration or failure rates.

```sql
-- Create monitoring table
CREATE TABLE pipeline_task_metrics (
  task_name VARCHAR,
  pipeline_run_id VARCHAR,
  started_at TIMESTAMP,
  completed_at TIMESTAMP,
  status VARCHAR, -- 'success' or 'failed'
  rows_processed INT,
  error_message VARCHAR,
  recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert example monitoring event
INSERT INTO pipeline_task_metrics VALUES
  ('ingest_job_postings', 'run_20250115_001', '2025-01-15 02:00:00', '2025-01-15 02:08:30', 'success', 14250, NULL, CURRENT_TIMESTAMP);

-- Query: flag tasks with unusual duration
SELECT
  task_name,
  DATE(started_at) as run_date,
  COUNT(*) as run_count,
  AVG(EXTRACT(EPOCH FROM (completed_at - started_at))) as avg_duration_seconds,
  MAX(EXTRACT(EPOCH FROM (completed_at - started_at))) as max_duration_seconds,
  SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failure_count,
  ROUND(100.0 * SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) / COUNT(*), 2) as failure_rate_pct
FROM pipeline_task_metrics
WHERE started_at >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY task_name, DATE(started_at)
HAVING
  MAX(EXTRACT(EPOCH FROM (completed_at - started_at))) > 
    AVG(EXTRACT(EPOCH FROM (completed_at - started_at))) * 3
  OR SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) > 0
ORDER BY run_date DESC, failure_rate_pct DESC;
```

## Notes

- **Common mistake:** Logging only pipeline-level success/failure. A pipeline marked "success" might have dropped 30% of rows in a transformation—you need granular metrics on every task and row counts in/out.
- **Intermittent failures hide in retry logic.** If your orchestrator auto-retries failed tasks, the retry succeeds but the original failure disappears from logs. Track both attempts and final outcomes.
- **Duration baselines drift.** Don't hardcode thresholds like "alert if > 10 minutes." Use rolling percentiles (e.g., p95 over the last 14 days) so you catch genuine regressions, not normal seasonal variation.
- **Connects to:** alerting (routing task failure notifications to the right team), SLOs (defining acceptable failure rates), and root cause analysis (storing error messages and stack traces alongside metrics).
- **Revisit:** How to aggregate metrics across many tasks into a single pipeline health score, and when to distinguish between transient failures (retry and move on) vs. persistent ones (page on-call).
