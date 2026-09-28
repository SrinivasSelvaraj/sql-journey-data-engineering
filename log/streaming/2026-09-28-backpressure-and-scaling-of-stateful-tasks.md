---
date: 2026-09-28
phase: streaming
topic: Backpressure and scaling of stateful tasks
---

# Backpressure and scaling of stateful tasks

*Streaming and distributed processing*

## Concept

Backpressure is the mechanism by which a downstream system signals to an upstream producer that it cannot keep pace with incoming data, forcing the producer to slow down or buffer strategically. In streaming systems, this prevents memory exhaustion and cascading failures—without it, a fast producer will overwhelm a slower consumer, causing queues to grow unbounded and eventually crash the application.

Stateful tasks make backpressure critical because they accumulate data in memory. If you're aggregating job postings by location or maintaining a rolling count of remote positions, the operator holds state that grows as pressure builds. A slow stateful aggregation receiving 10,000 events/sec but only processing 1,000/sec will accumulate 9,000 events/sec in its internal buffer; within minutes or hours, it runs out of heap.

Without backpressure, the only signal of failure is an OutOfMemoryException or hung task. With backpressure, the source slows or batches earlier, and operators downstream of the slow stateful task can skip or drop low-priority events. This is why Kafka consumers use offset commits sparingly during high load, why Flink's network stacks use credit-based flow control, and why designing stateless or time-windowed operations upstream of expensive stateful ones matters.

## Practice

**Problem:** You ingest job postings in real-time and compute a 1-hour rolling count of remote positions by job title. Traffic spikes during peak hours cause the aggregation to fall behind. How do you design the pipeline to handle backpressure without losing data or crashing?

```sql
-- Stateless upstream: extract remote positions only (filter early)
CREATE VIEW remote_postings_stream AS
SELECT job_id, job_title_short, job_posted_date
FROM job_postings_fact
WHERE job_work_from_home = TRUE;

-- Stateful aggregation with watermarking and session management
-- Use tumbling windows (1 hour) instead of sliding to reduce state
SELECT 
  TUMBLE_START(job_posted_date, INTERVAL '1 HOUR') AS window_start,
  job_title_short,
  COUNT(*) AS remote_count
FROM remote_postings_stream
GROUP BY TUMBLE(job_posted_date, INTERVAL '1 HOUR'), job_title_short;

-- Backpressure strategy: emit counts only when window closes
-- If aggregation stalls, source commits offsets lazily (e.g., every 5 min)
-- downstream consumers (alerts, dashboards) read from Kafka topic holding results
-- Never read directly from operator state
```

## Notes

- **State size explosion:** Avoid open-ended session windows without timeout logic; always pair stateful ops with TTL (time-to-live) cleanup to bound heap usage.
- **Filter early:** Apply `WHERE` clauses and map-only transformations before stateful operators; backpressure is most effective when you reduce cardinality upstream.
- **Watermarking:** Late-arriving data and out-of-order events complicate state management. Set explicit watermark strategy (e.g., 10 min allowed lateness) so the engine can evict old state safely.
- **Adjacent topics:** Relates closely to exactly-once semantics, offset management, and checkpoint alignment in distributed systems; also connects to rate limiting and adaptive load shedding strategies.
- **Common mistake:** Relying on fast deserialization or cheap transformations to "absorb" backpressure; a 100ns per-record operation on 1M/sec is still 100ms overhead, so stateful tasks are the real bottleneck.
