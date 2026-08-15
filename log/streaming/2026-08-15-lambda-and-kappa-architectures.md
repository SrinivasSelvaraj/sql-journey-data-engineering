---
date: 2026-08-15
phase: streaming
topic: Lambda and Kappa architectures
---

# Lambda and Kappa architectures

*Streaming and distributed processing*

## Concept

Lambda architecture processes data through two parallel paths: a *batch layer* (high-latency, accurate historical computations) and a *speed layer* (low-latency, approximate real-time results). Results are merged at query time. This dual approach handles the fundamental tradeoff that strict consistency at scale requires batching, while low latency requires loose consistency.

Kappa architecture simplifies this by using a single *streaming* path with a replayable event log (like Kafka), eliminating the batch layer entirely. When you need to recompute, you replay the stream rather than maintain separate code paths. This matters when your data never stops arriving (IoT sensors, clickstreams, job postings) and arrives out of order—you cannot assume a clean daily snapshot.

Without these patterns, late-arriving data corrupts aggregates, skewed partitions cause bottlenecks, and simultaneous demands for speed *and* accuracy force impossible tradeoffs. Lambda lets you serve both; Kappa trades operational complexity for code elegance when replay is feasible.

## Practice

**Problem:** Job postings arrive continuously and out-of-order. You need a 15-minute moving average of salaries *and* an accurate monthly salary report. Late postings (posted date before today) must update both paths.

```sql
-- Kappa-style: single streaming source with state store
-- Assume a Kafka topic: job_postings_stream
-- Replayed from offset 0 for recomputation

-- Speed layer: 15-minute tumbling window (approximate)
SELECT
  TUMBLE_START(job_posted_date, INTERVAL '15' MINUTE) AS window_start,
  COUNT(*) AS job_count,
  AVG(salary_year_avg) AS avg_salary_15min
FROM job_postings_stream
WHERE salary_year_avg IS NOT NULL
GROUP BY TUMBLE(job_posted_date, INTERVAL '15' MINUTE)
EMIT BEFORE UPDATE;  -- emit partial results

-- Batch layer: daily accuracy (materialized each night)
INSERT INTO job_postings_daily_summary
SELECT
  DATE_TRUNC('day', job_posted_date) AS posted_day,
  COUNT(*) AS job_count,
  AVG(salary_year_avg) AS avg_salary,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) AS median_salary
FROM job_postings_fact
WHERE DATE_TRUNC('day', job_posted_date) = CURRENT_DATE - INTERVAL '1' DAY
GROUP BY DATE_TRUNC('day', job_posted_date);

-- Query-time merge: serve latest speed result, fallback to batch if older than 15 min
SELECT
  COALESCE(speed.window_start, batch.posted_day) AS period,
  COALESCE(speed.avg_salary_15min, batch.avg_salary) AS salary_avg
FROM speed_layer_table speed
FULL OUTER JOIN job_postings_daily_summary batch
  ON DATE(speed.window_start) = batch.posted_day
WHERE speed.window_start > NOW() - INTERVAL '15' MINUTE
ORDER BY period DESC;
```

## Notes

- **Lambda maintenance burden:** Two code paths (Spark batch + Flink stream) means duplicate logic and divergence bugs. Use it only when batch latency is genuinely unacceptable.
- **Kappa's replay assumption:** Event logs must be immutable and retained long enough to recompute months of history. Schema evolution and compacted topics break this.
- **Out-of-order handling:** Both require watermarking (late-arriving tolerance windows) and idempotent state updates; sessionization and join windows become complex.
- **Connected concept:** Event sourcing (append-only event stores) is the persistence pattern that makes Kappa practical; without it, replay is impossible.
- **Revisit:** Exactly-once semantics, late-data windows (allowed lateness), and cost tradeoffs between storage (retain full stream) and compute (re-run batch).
