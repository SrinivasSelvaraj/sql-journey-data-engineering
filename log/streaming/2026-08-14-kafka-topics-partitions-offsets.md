---
date: 2026-08-14
phase: streaming
topic: Kafka: topics, partitions, offsets
---

# Kafka: topics, partitions, offsets

*Streaming and distributed processing*

## Concept

A Kafka **topic** is a named stream of events; a **partition** is an ordered, immutable sequence of messages within that topic. Each message in a partition is assigned an **offset**—a unique, monotonically increasing integer. When a consumer reads from a topic, it tracks which offset it has processed, allowing it to resume from where it left off if it crashes or scales horizontally.

This matters because real data arrives out of order and never stops. Without partitions, a single broker becomes a bottleneck; without offsets, there is no way to know which events you've already processed or to replay history. Partitions enable parallelism (multiple consumers can read different partitions simultaneously), and offsets enable exactly-once or at-least-once semantics in downstream pipelines.

Without this model, you lose ordering guarantees within a stream, cannot scale consumption, and have no replay capability—meaning lost events or duplicate processing become inevitable in any fault scenario.

## Practice

**Problem:** You ingest job postings into Kafka with 5 partitions. A consumer application processes them to compute rolling 30-day salary averages by location. The app crashes after processing offset 10,000 on partition 2, but has only processed up to offset 8,500 on partitions 0, 1, 3, and 4. On restart, how do you ensure you don't reprocess or skip records?

```sql
-- Track consumer offsets per partition (typically stored in Kafka's __consumer_offsets topic)
-- For resumption logic:
SELECT 
  partition_id,
  MAX(processed_offset) AS last_safe_offset,
  job_location,
  AVG(salary_year_avg) AS avg_salary_30d
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - 30
  AND (partition_id, offset) > (
    SELECT partition_id, last_committed_offset
    FROM consumer_offsets
    WHERE consumer_group = 'salary_aggregator'
  )
GROUP BY partition_id, job_location;
```

On restart, the consumer seeks to its last committed offset per partition and resumes from there—partition 2 restarts at 10,001, partition 0 at 8,501, etc.

## Notes

- **Offset commits are not automatic:** you must explicitly commit offsets (after processing, not before) to avoid reprocessing or data loss. Commit frequency trades safety against throughput.
- **Partition count is immutable after topic creation:** choose it based on expected throughput and consumer parallelism; too few and you lose concurrency, too many and you fragment state unnecessarily.
- **Ordering guarantee is per-partition only:** if you need global ordering of job postings by `job_posted_date`, use a consistent key (e.g., `job_location`) to ensure same location always routes to the same partition.
- **Consumer lag** (current offset – latest offset) signals whether your consumer is keeping up; monitor it to detect backpressure or failures.
- **Adjacent topics:** consumer groups, rebalancing, state stores (for windowed aggregations), and dead-letter queues for handling poison messages.
