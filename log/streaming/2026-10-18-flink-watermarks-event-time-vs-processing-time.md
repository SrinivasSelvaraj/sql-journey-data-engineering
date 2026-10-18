---
date: 2026-10-18
phase: streaming
topic: Flink watermarks: event time vs processing time
---

# Flink watermarks: event time vs processing time

*Streaming and distributed processing*

## Concept

Event time is when data was actually created (e.g., when a job was posted); processing time is when your Flink job encounters and processes that record. In streaming systems, these diverge because records arrive out of order and may be delayed. A **watermark** is a progress signal that tells Flink "all events with timestamp ≤ X have (probably) arrived," allowing windowed aggregations to close and emit results rather than waiting forever.

Without watermarks, a 1-hour tumbling window would never know when to fire—it cannot assume late data will never come. Watermarks solve this by being a heuristic commitment: they allow you to trade a small amount of late data loss (or late-arriving handling logic) for the ability to produce timely results. If your source system guarantees events arrive within 5 minutes of their event time, you'd set a 5-minute allowed lateness and watermark accordingly.

This matters most when computing aggregations (revenue per day, job postings per hour, average salary by region) where you need a window to close. Without explicit watermark strategy, your pipeline either blocks indefinitely waiting for the "true" completion of time, or emits incomplete results.

## Practice

**Problem:** You receive job postings in a Kafka topic. Records have `job_posted_date` (event time) but arrive at unpredictable intervals—sometimes a posting from 2 hours ago arrives just now. You need to compute the count of remote jobs posted *per hour*, and emit that count after the hour closes, accepting that postings arriving more than 10 minutes late will be discarded.

```sql
-- Flink SQL approach using watermarks
CREATE TABLE job_postings_source (
  job_id INT,
  job_title_short STRING,
  job_posted_date TIMESTAMP(3),
  job_work_from_home BOOLEAN,
  job_location STRING,
  WATERMARK FOR job_posted_date AS job_posted_date - INTERVAL '10' SECOND
) WITH (
  'connector' = 'kafka',
  'topic' = 'job_postings',
  'properties.bootstrap.servers' = 'localhost:9092',
  'format' = 'json'
);

SELECT
  TUMBLE_START(job_posted_date, INTERVAL '1' HOUR) AS hour_window,
  COUNT(*) AS remote_job_count
FROM job_postings_source
WHERE job_work_from_home = true
GROUP BY TUMBLE(job_posted_date, INTERVAL '1' HOUR);
```

The `WATERMARK FOR job_posted_date AS job_posted_date - INTERVAL '10' SECOND` declares that you allow 10 seconds of lateness. After that threshold, the 1-hour window emits and closes.

## Notes

- **Common mistake:** Confusing watermark delay with window size. A watermark of -10s means "close the window 10s after its end time"; the window size (1 hour) is independent. Setting watermark equal to window size causes late data to arrive before windows close.

- **Allowed lateness vs. side outputs:** Flink lets you define `allowedLateness()` separately from watermarks. Records arriving after the watermark but within allowed lateness can update the result and trigger a new emit; this requires careful downstream deduplication logic.

- **Watermark strategy depends on source:** Kafka offsets don't carry timing metadata, so you must infer watermarks from the record's embedded timestamp field. Database CDC sources (Debezium) have different timing semantics and may need custom `WatermarkStrategy` implementations.

- **Idleness and backpressure:** If one partition of your Kafka topic stops receiving data, its watermark stalls, blocking the entire job's progress. Use `withIdleness()` to advance watermarks even when a partition is silent.

- **Revisit:** Session windows (which close after inactivity rather than fixed time) rely on watermarks differently; also explore custom watermark assignments for non-monotonic timestamps and the relationship between watermarks and exactly-once semantics.
