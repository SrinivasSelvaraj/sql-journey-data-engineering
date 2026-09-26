---
date: 2026-09-26
phase: streaming
topic: Log compaction and retention policy trade-offs
---

# Log compaction and retention policy trade-offs

*Streaming and distributed processing*

## Concept

Log compaction and retention policies determine how long streaming data is kept and in what form. **Log compaction** keeps only the latest value per key, discarding older versions; **retention** simply deletes old messages after a time or size threshold. In distributed streaming systems (Kafka, Pulsar), these policies directly affect recovery behavior, storage costs, and the ability to replay or backfill state.

Without a retention policy, logs grow unbounded and eventually exhaust storage. Without compaction, you retain full history even when only the current state matters—expensive and slow to process. The trade-off: compaction saves space and speeds up state rebuilds (useful for changelogs and reference data), but you lose historical audit trails. Retention alone is simpler but wastes space on redundant updates to the same entity.

The choice depends on your use case. A changelog topic tracking customer profiles benefits from compaction; you only care about the latest address or payment method. An events topic (pageviews, purchases) typically uses time-based retention because each event is distinct and immutable. Many systems use *both*: compact for state topics, retain for event topics.

## Practice

**Problem:** Your job_postings_fact table is fed from a Kafka topic where job_id is the key. Job descriptions are frequently updated (title changes, salary corrections, location shifts). You want to minimize storage in Kafka while ensuring you can always recover the current state of each job posting, but you also need a 90-day audit trail of all changes.

**Solution:**

```sql
-- Split into two topics:

-- 1. Compacted topic: stores latest job state only
CREATE TOPIC job_postings_state WITH (
  'cleanup.policy' = 'compact',
  'min.compaction.lag.ms' = 3600000,      -- 1 hour: allow time for updates to batch
  'segment.ms' = 86400000,                -- 1 day segments for compaction
  'retention.ms' = 2592000000              -- 30 days: keep old segments before deletion
);

-- 2. Event topic: immutable changes, time-based retention
CREATE TOPIC job_postings_changes WITH (
  'cleanup.policy' = 'delete',
  'retention.ms' = 7776000000              -- 90 days audit trail
);

-- Producer logic (pseudocode):
-- Send to both:
-- - job_postings_state: key=job_id, value={job_id, title, salary, location, posted_date}
-- - job_postings_changes: key=job_id, value={change_id, old_salary, new_salary, timestamp, operation}

-- Consumer for current state (recovery):
-- Read job_postings_state compacted topic → instant rebuild of job_postings_fact

-- Consumer for audit (compliance):
-- Read job_postings_changes with 90-day retention → track salary history, location moves
```

## Notes

- **Compaction lag matters:** If you compact immediately, a consumer reading from the beginning races the compaction thread; set `min.compaction.lag.ms` to ensure updates batch first.
- **Segment boundaries:** Compaction happens *between* segments, not within them. Tune `segment.ms` to balance latency (smaller = more compaction) vs. overhead (larger = fewer merges).
- **Dual-topic pattern:** Separate state (compacted) from events (deleted retention). State topics are narrow, fast to replay; event topics are wide, immutable, auditable.
- **Adjacent: changelog databases** (RocksDB, state stores in Flink/Kafka Streams) implement compaction locally; understanding broker-level compaction clarifies why your state store also needs cleanup policies.
- **Revisit:** Partition key design affects compaction efficiency—high-cardinality keys (user_id) compact slowly; low-cardinality (job_id) compact aggressively. Also consider idempotency: without compaction guarantees, duplicate sends can bloat historical audit trails.
