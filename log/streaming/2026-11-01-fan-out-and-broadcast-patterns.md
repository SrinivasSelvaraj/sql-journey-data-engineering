---
date: 2026-11-01
phase: streaming
topic: Fan-out and broadcast patterns
---

# Fan-out and broadcast patterns

*Streaming and distributed processing*

## Concept

Fan-out and broadcast patterns handle scenarios where a single event or batch must flow to multiple downstream consumers or processing paths without duplication or loss. In streaming systems, a source produces data once but many consumers need it—fan-out ensures each consumer receives the full dataset independently, while broadcast distributes that same data to all parallel workers in a distributed compute job. Without these patterns, you either lose data (if one consumer blocks others), create bottlenecks (serializing access), or duplicate work (each consumer re-reading from the source).

The practical challenge emerges when your stream has high volume or multiple independent purposes: one team needs job postings for search indexing, another for salary analytics, a third for fraud detection. A naive pipeline that chains these sequentially introduces latency and coupling. Fan-out lets them consume in parallel; broadcast ensures distributed workers don't miss partitions. This becomes critical at scale—a single slow consumer can back up the entire pipeline if not isolated.

## Practice

**Problem:** You have an incoming stream of job postings. One consumer must update a search index in near real-time, another must compute rolling 7-day salary statistics by location, and a third must flag suspicious posting patterns. How do you ensure all three consume every posting without one blocking the others?

```sql
-- Fan-out using topic/queue duplication (Kafka, Pulsar pattern)
-- Single source writes to 3 independent topics
INSERT INTO search_index_topic
SELECT job_id, job_title_short, job_location, job_posted_date
FROM job_postings_stream;

INSERT INTO salary_stats_topic
SELECT job_id, job_location, salary_year_avg, job_posted_date
FROM job_postings_stream;

INSERT INTO fraud_detection_topic
SELECT job_id, job_title_short, job_work_from_home, job_posted_date, job_location
FROM job_postings_stream;

-- Broadcast pattern (Spark Streaming / distributed SQL)
-- Each worker receives full reference data before processing partitioned stream
WITH broadcast_locations AS (
  SELECT DISTINCT job_location FROM job_postings_fact
)
SELECT 
  jp.job_id,
  jp.salary_year_avg,
  CASE WHEN bl.job_location IS NULL THEN 'unknown' ELSE 'known' END AS location_status
FROM job_postings_stream jp
LEFT JOIN broadcast_locations bl ON jp.job_location = bl.job_location;
```

## Notes

- **Common mistake:** Treating fan-out and broadcast as identical—fan-out sends data to *multiple independent downstream systems*; broadcast sends *the same data to all partitions of a single computation*. Conflating them causes either data duplication or incomplete worker state.

- **Backpressure isolation:** Fan-out only works if each consumer has its own queue/buffer. If consumer A stalls, it should not slow consumer B. Shared buffers defeat the pattern.

- **Connects to:** Event sourcing (one immutable event, multiple projections), CQRS (Command Query Responsibility Segregation—different models reading the same source), and lambda/kappa architectures (batch and stream consuming the same data independently).

- **Broadcast gotcha:** The "broadcast" dataset must fit in worker memory. For large reference tables, use a distributed join or lookup service instead. Watch for stale broadcasts—refresh cadence matters.

- **Revisit:** How does your messaging layer guarantee delivery semantics (exactly-once, at-least-once) across multiple fan-out paths? Exactly-once in one topic doesn't mean exactly-once across three. Track offset/checkpoint state per consumer group.
