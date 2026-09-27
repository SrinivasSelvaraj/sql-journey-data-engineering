---
date: 2026-09-27
phase: streaming
topic: Watermark idleness and stalled source detection
---

# Watermark idleness and stalled source detection

*Streaming and distributed processing*

## Concept

Watermark idleness occurs when a streaming source stops emitting events for a period of time, causing the watermark (a timestamp tracking progress through event time) to stall. Without explicit idle detection, the processing engine has no way to distinguish between "events are delayed" and "the source is actually quiet," leading to indefinite buffering of downstream data and delayed or stuck aggregations. This is especially problematic in windowed operations or joins that depend on watermark advancement to emit results.

Stalled source detection addresses this by allowing you to declare that if no events arrive within a threshold duration, the watermark should advance anyway. This prevents late-arriving windows from blocking indefinitely and ensures that triggers and time-based operations complete even when data stops flowing. It's critical in multi-source streaming pipelines where one source may be legitimately idle while others remain active.

Without watermark idleness handling, you may see windows that never close, joins that never unblock, and alerts that fire minutes or hours late—all because the engine is still waiting for data that will never arrive.

## Practice

**Problem:** A job posting analytics pipeline ingests job postings from multiple regions. The European region occasionally goes quiet during off-hours, but the watermark stalls completely, blocking downstream aggregations (e.g., "jobs posted per hour") from emitting results. You need to advance the watermark even if no EU jobs arrive for 30 minutes.

```sql
SELECT
  TUMBLE_START(job_posted_date, INTERVAL '1' HOUR) AS hour_start,
  COUNT(*) AS jobs_posted,
  AVG(salary_year_avg) AS avg_salary
FROM job_postings_fact
WHERE job_location LIKE '%Europe%'
GROUP BY TUMBLE(job_posted_date, INTERVAL '1' HOUR)
;

-- Enable idle source detection (framework-dependent; example for Flink):
-- StreamExecutionEnvironment.enableChangelogStateBackend()
-- env.getConfig().setIdleStateRetentionTime(
--   Time.minutes(30),
--   Time.minutes(31)
-- );
--
-- For Kafka/Pub/Sub source, set explicit watermark strategy:
-- WatermarkStrategy.forBoundedOutOfOrderness(Duration.ofMinutes(15))
--   .withIdleness(Duration.ofMinutes(30))
```

## Notes

- **Mistake:** Confusing watermark idleness with source lag; idleness is about *no events at all*, not slow events. Setting the idle threshold too low causes false-positive watermark advances.
- **Mistake:** Forgetting that idleness is per-partition or per-source; if you have multiple Kafka partitions, some may be idle while others are active—idleness detection must be partition-aware.
- **Connection:** Related to allowed lateness and side outputs; idle detection ensures windows actually close so late data can be routed correctly.
- **Connection:** Ties into SLA monitoring and alerting; detecting stalled sources is essential before users notice missing dashboards.
- **Revisit:** How watermark propagation works in multi-stage pipelines and how idleness interacts with backpressure and fan-out patterns.
