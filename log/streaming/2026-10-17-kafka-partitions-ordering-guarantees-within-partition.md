---
date: 2026-10-17
phase: streaming
topic: Kafka partitions: ordering guarantees within partition
---

# Kafka partitions: ordering guarantees within partition

*Streaming and distributed processing*

## Concept

Kafka guarantees that messages sent to the **same partition** are delivered to consumers in the exact order they were written. This is critical for streaming systems where causality and state mutations matter: if you post a job, then immediately update its salary, consumers must see those events in that sequence, not reversed. Without partition-level ordering, a consumer might process the salary update before seeing the job creation, leaving it trying to update a non-existent record.

Ordering is guaranteed *within* a partition only—not across partitions. If a single producer sends two messages to partition 0, they arrive in order; if those messages fan across partitions 0 and 1, each partition respects its own order, but a consumer reading both sees no global ordering. This is why keying (routing related events to the same partition via a key like `job_id`) becomes essential in stateful streaming systems.

The ordering contract is maintained as long as the producer sends synchronously (waiting for acknowledgment) and the consumer processes sequentially. Async producers, retries, and parallel consumption can break ordering guarantees—you must be explicit about trading off latency for ordering.

## Practice

**Problem:** Job postings arrive as `created` and `updated` events on the same Kafka topic. You need to ensure that for each job, the `created` event is always processed before any `updated` events, so your fact table reflects the correct state.

```sql
-- In your streaming consumer (pseudo-SQL; actual implementation is Flink/Spark/Kafka Streams):
-- Assume events arrive from Kafka with: event_type, job_id, event_timestamp, payload

INSERT INTO job_postings_fact
SELECT 
    CAST(JSON_EXTRACT(payload, '$.job_id') AS INT) AS job_id,
    JSON_EXTRACT(payload, '$.job_title_short') AS job_title_short,
    JSON_EXTRACT(payload, '$.salary_year_avg') AS salary_year_avg,
    CAST(JSON_EXTRACT(payload, '$.job_work_from_home') AS BOOLEAN) AS job_work_from_home,
    CAST(JSON_EXTRACT(payload, '$.job_posted_date') AS DATE) AS job_posted_date,
    JSON_EXTRACT(payload, '$.job_location') AS job_location
FROM kafka_topic
WHERE event_type = 'created'
  AND partition_key = job_id  -- Ensure all job events route to same partition
ORDER BY event_timestamp ASC;  -- Consume in order within partition
```

Key: the Kafka producer **must hash messages by `job_id`** so all events for the same job land in one partition, and the consumer must process messages sequentially without parallelism or out-of-order retries.

## Notes

- **Common mistake:** Assuming global ordering across partitions—Kafka does *not* guarantee this. Always think partition-first.
- **Keying is non-negotiable:** If you don't explicitly set a key (or set it to null), Kafka round-robins across partitions, destroying ordering for stateful operations.
- **Relates to:** Exactly-once semantics (ordering alone isn't enough; you also need idempotent writes), consumer group rebalancing (can cause duplicate processing if not offset-managed carefully), and changelog compaction (relies on key-level ordering to collapse updates).
- **Revisit:** How offset management and consumer lag interact with ordering; test what happens when a producer retries—does Kafka reorder, or do duplicates appear in-order?
- **Trade-off:** Single partition per key simplifies ordering but creates a bottleneck; consider sharding by secondary key or time window if throughput is critical.
