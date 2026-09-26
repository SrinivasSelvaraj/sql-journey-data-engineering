---
date: 2026-09-26
phase: streaming
topic: Consumer groups and offset management in Kafka
---

# Consumer groups and offset management in Kafka

*Streaming and distributed processing*

## Concept

A **consumer group** is a set of Kafka consumers that collectively read from one or more topics, with each partition assigned to exactly one consumer in the group. This enables **parallelism and fault tolerance**: multiple consumers can process the same topic independently, and if one fails, Kafka automatically rebalances partitions among remaining members. **Offset management** tracks the position (message sequence number) each consumer has read up to, allowing resumption without data loss or reprocessing the entire stream.

Without consumer groups and offset tracking, every application would need to restart from the earliest message or track state manually—leading to either duplicates (reprocessing old data) or gaps (missing new data). In production streaming, this matters intensely: a job ingestion pipeline with 10 partitions needs 10 parallel consumers to avoid a single bottleneck, and if a consumer crashes mid-batch, you must know exactly where to resume.

Offset commits are the critical mechanism: when a consumer **commits** an offset, it tells Kafka "I have successfully processed all messages up to this point." This state lives in a special internal topic (`__consumer_offsets`) or external store. If commits are lost or lag behind actual processing, rebalances and restarts become dangerous—you either re-ingest stale data or skip valid records.

## Practice

**Problem:** A Kafka topic `job_postings` streams new job postings in real-time. You have a consumer group `salary_aggregators` with three consumers, each reading different partitions. One consumer crashes after processing 1,500 messages but before committing. When it restarts, how do you ensure it resumes from the last safe offset without duplicating records?

```sql
-- Simulated scenario: track offsets and consumer state
-- In practice, this is managed by Kafka brokers, but reasoning through it:

-- Consumer commits offset 1,500 after successfully writing to job_postings_fact
-- Offset is stored: (group_id='salary_aggregators', topic='job_postings', partition=0, offset=1500)

-- On restart, consumer queries: "What is my committed offset for partition 0?"
-- Kafka responds: offset=1500
-- Consumer starts consuming from message 1501 onward

-- To simulate this in SQL, track consumer progress:
CREATE TABLE consumer_offset_tracking (
  consumer_group_id STRING,
  topic STRING,
  partition_id INT,
  last_committed_offset BIGINT,
  committed_timestamp TIMESTAMP,
  PRIMARY KEY (consumer_group_id, topic, partition_id)
);

INSERT INTO consumer_offset_tracking VALUES
  ('salary_aggregators', 'job_postings', 0, 1500, CURRENT_TIMESTAMP);

-- On crash recovery, a consumer joins the group; Kafka rebalances and assigns
-- partition 0 to a new/restarted consumer. It fetches the committed offset:
SELECT last_committed_offset 
FROM consumer_offset_tracking
WHERE consumer_group_id = 'salary_aggregators' 
  AND topic = 'job_postings' 
  AND partition_id = 0;
-- Result: 1500 → resume consuming from offset 1501
```

## Notes

- **Auto-commit trap:** setting `enable.auto.commit=true` with a short interval can commit offsets before data is written to your fact table, causing data loss. Prefer manual commits after successful ingestion.
- **Rebalancing lag:** during rebalancing (when consumers join/leave), no messages are consumed. Long rebalances kill real-time SLAs; minimize consumer churn and tune session timeout carefully.
- **Offset reset strategy:** if committed offsets are lost or a consumer lags beyond retention, `auto.offset.reset` controls fallback (earliest/latest/none). Choosing `latest` silently skips historical data; `earliest` risks reprocessing months of backlog.
- **Multiple consumer groups on one topic:** different teams can run separate groups on the same topic (e.g., `salary_aggregators` vs. `location_analyzers`), each maintaining independent offsets—enables decoupled pipelines.
- **Related:** partition assignment strategies (range, round-robin, sticky), exactly-once vs. at-least-once semantics, and dead-letter queues for poison messages.
