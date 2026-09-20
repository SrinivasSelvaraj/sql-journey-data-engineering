---
date: 2026-09-20
phase: pipelines
topic: Lambda architecture: batch and streaming merge
---

# Lambda architecture: batch and streaming merge

*Pipelines and orchestration*

## Concept

Lambda architecture splits processing into two parallel paths: a **batch layer** that recomputes truth from immutable historical data, and a **streaming layer** that handles low-latency updates on recent events. A **serving layer** merges results from both, presenting a unified view. This matters because batch is slow but correct (handles late arrivals, fixes errors), while streaming is fast but approximate (drops records under load, has ordering issues). Without intentional merging logic, you either serve stale data or lose historical context when a streaming consumer crashes.

The key tension: a job posting's salary might arrive 3 days late in your stream, but your batch job already ran yesterday. If you don't reconcile, analytics either double-count or miss updates. The merge layer must define a "source of truth" rule—usually "batch wins for [cutoff_date], stream wins for [recent_date]"—and handle the overlap window where both exist.

## Practice

**Problem:** Your job_postings_fact table needs to reflect salary corrections that come late. Batch runs daily at 2 AM on data through yesterday. Streaming ingests updates real-time but can lose records. Build a query that serves the current view, preferring batch for old data and stream for today's.

```sql
WITH batch_layer AS (
  SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
  FROM batch.job_postings_fact
  WHERE job_posted_date < CURRENT_DATE
),
streaming_layer AS (
  SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
  FROM stream.job_postings_updates
  WHERE job_posted_date >= CURRENT_DATE
    AND ingestion_timestamp < CURRENT_TIMESTAMP - INTERVAL 5 MINUTE  -- allow 5min buffer for late arrivals
),
merged AS (
  SELECT * FROM batch_layer
  UNION ALL
  SELECT * FROM streaming_layer
)
SELECT DISTINCT ON (job_id) *
FROM merged
ORDER BY job_id, job_posted_date DESC;
```

## Notes

- **Common mistake:** Treating the overlap window as "don't worry about it." Even a 1-hour gap causes duplicates or missing records. Define the cutoff date explicitly in code.
- **Rerun safety:** Batch must be idempotent (same input → same output). If it's not, lambda breaks because you can't safely re-merge after a failure.
- **Streaming schema drift:** Stream and batch schemas can diverge. Add a schema validation layer before merge, or use a union-compatible format (Avro, Protobuf).
- **Connects to:** Kappa architecture (streaming-only alternative), exactly-once semantics, watermarks in Flink/Spark Structured Streaming.
- **Worth revisiting:** How to handle late-arriving dimension updates (e.g., job location corrected after posting), and whether your merge layer itself needs to be monitored for staleness.
