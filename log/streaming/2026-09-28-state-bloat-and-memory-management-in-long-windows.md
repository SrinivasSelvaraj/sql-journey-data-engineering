---
date: 2026-09-28
phase: streaming
topic: State bloat and memory management in long windows
---

# State bloat and memory management in long windows

*Streaming and distributed processing*

## Concept

State bloat occurs when a streaming aggregation or windowed operation accumulates intermediate results—counts, sums, sketches, or buffered events—without ever discarding old data. In long-running windows (hours, days, or indefinite session windows), memory usage grows linearly with time rather than staying bounded, eventually causing out-of-memory failures or garbage collection pauses that degrade throughput.

This matters most in systems like Flink, Spark Streaming, or Kafka Streams where state is held in memory across micro-batches or event time. A simple COUNT aggregation over a 7-day tumbling window seems safe until you realize: if 100k events arrive per second, you're buffering 60.48 billion events before the window closes. Without explicit state eviction, the JVM drowns.

The solution is **time-aware state cleanup**: remove state entries that are no longer needed for correctness. This requires understanding your window semantics—when can you safely throw away aggregates? Allowed lateness, output triggers, and cleanup timing are the levers you control.

## Practice

**Problem:** Calculate rolling 30-day average salary by job location. Events arrive out of order (up to 2 days late). Without cleanup, state grows unboundedly even though you only need the last 30 days of salary data per location.

```sql
SELECT
  window_start,
  window_end,
  job_location,
  AVG(salary_year_avg) AS avg_salary_30d,
  COUNT(*) AS job_count
FROM job_postings_fact
GROUP BY
  TUMBLE(job_posted_date, INTERVAL '1' DAY),
  job_location
WHERE job_posted_date >= CURRENT_TIMESTAMP - INTERVAL '30' DAY
  AND job_posted_date < CURRENT_TIMESTAMP
EMIT BEFORE WATERMARK AFTER INTERVAL '2' DAY  -- allow 2-day lateness
;

-- State retention: explicitly drop state older than 32 days
SET 'table.exec.state.ttl' = '32 DAY';
```

The `table.exec.state.ttl` parameter tells the engine to delete intermediate state (partial aggregates, buffered records) for windows that closed more than 32 days ago (30-day window + 2-day allowed lateness). Without this, job_location state keys accumulate forever.

## Notes

- **Confusing allowed lateness with state TTL:** Allowed lateness controls output correctness; state TTL controls memory. You need both, and TTL should always exceed window size + allowed lateness.
- **Checkpoint size explosion:** State bloat shows up first as growing checkpoint size on disk. Monitor RocksDB or in-memory state backend metrics; if checkpoints grow 10% per hour, you're leaking state.
- **Session windows are the worst offender:** Unbounded session windows never close naturally. Use inactivity gaps (e.g., 1-hour silence = end session) combined with aggressive TTL to prevent infinite state accumulation.
- **Connects to:** watermark management, output modes (APPEND vs UPDATE), and backpressure—if state is bloating, your pipeline is likely falling behind and not emitting results, so data piles up upstream too.
- **Revisit:** How does your chosen backend (heap, RocksDB, external store) affect TTL behavior? RocksDB compaction timing matters; heap TTL is immediate but pauses the JVM.
