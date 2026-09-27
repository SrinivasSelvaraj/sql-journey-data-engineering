---
date: 2026-09-27
phase: streaming
topic: Source-side watermarks vs operator-side watermarks
---

# Source-side watermarks vs operator-side watermarks

*Streaming and distributed processing*

## Concept

A **watermark** is a signal that tells a streaming system "all events with timestamps ≤ this value have arrived." Without it, the system cannot know when to finalize a window and produce a result.

**Source-side watermarks** are generated at the data origin (e.g., a message broker, sensor, API log) and embedded in the event stream itself. They reflect the producer's understanding of data completeness. **Operator-side watermarks** are computed downstream by the streaming engine (Flink, Spark Structured Streaming, Kafka Streams) based on observed event timestamps within each operator or stage. Source-side watermarks are more reliable because they account for delays and out-of-order arrivals at the source; operator-side watermarks can only react to what they see locally and may be influenced by slow consumers or operator parallelism.

Without watermarks, time-windowed aggregations (hourly revenue by location, daily job posting counts) either never close their windows—blocking results indefinitely—or close them arbitrarily, producing incomplete or incorrect answers. Late-arriving events cause either silent data loss or continuous re-computation of already-emitted results.

## Practice

**Problem:** You ingest job postings from multiple regional APIs with variable latency. Some postings arrive 2–3 hours late. You need to compute hourly rolling counts of new postings by location, closing the window 10 minutes after the hour ends, and handling late arrivals separately.

```sql
-- Assume Kafka topic 'job_postings_stream' with watermark embedded in schema
CREATE TABLE job_postings_watermarked AS
SELECT
  job_id,
  job_location,
  job_posted_date,
  CAST(job_posted_date AS TIMESTAMP) AS event_time,
  watermark  -- source-side watermark from Kafka producer
FROM kafka_source('job_postings_stream')
WHERE watermark IS NOT NULL;

-- Tumbling 1-hour window with 10-minute allowed lateness
SELECT
  TUMBLE_START(event_time, INTERVAL '1' HOUR) AS window_start,
  job_location,
  COUNT(*) AS posting_count,
  MAX(watermark) AS max_watermark_in_window
FROM job_postings_watermarked
GROUP BY
  TUMBLE(event_time, INTERVAL '1' HOUR),
  job_location
HAVING MAX(watermark) >= TUMBLE_END(event_time, INTERVAL '1' HOUR) + INTERVAL '10' MINUTE
ORDER BY window_start, job_location;

-- Side table for late-arriving postings (after window closure)
CREATE TABLE late_postings AS
SELECT
  job_id,
  job_location,
  event_time,
  CURRENT_TIMESTAMP AS arrival_time,
  CURRENT_TIMESTAMP - CAST(event_time AS TIMESTAMP) AS lateness_seconds
FROM job_postings_watermarked
WHERE event_time < CURRENT_TIMESTAMP - INTERVAL '70' MINUTE;
```

## Notes

- **Confusing watermark generation with watermark advancement:** A watermark is only useful when *progressed forward*. A stuck watermark (e.g., operator-side in a single slow partition) blocks all downstream windows; monitor watermark lag as a first-class metric.
- **Source-side is harder but worth it:** Generating watermarks at the producer (e.g., Kafka Connect with timestamp metadata, Pulsar event time tracking) requires coordination, but it survives repartitioning and operator reshuffling; operator-side watermarks can regress or stall during rebalancing.
- **Allowed lateness vs. watermark grace period:** These are related but distinct. Watermark allows you to know *when* to emit; allowed lateness tells the engine *how long* to keep state after emission. Both must be tuned together.
- **Connects to:** session windows (lateness matters more), side outputs (to capture late data), backpressure and consumer lag (watermark lag is often a symptom of downstream congestion).
- **Revisit when:** Your windowed aggregation produces incomplete or duplicate results; watermark lag is creeping upward; you're using `SESSION_WINDOW()` and seeing unexpected window splits.
