---
date: 2026-09-06
phase: streaming
topic: State backends: RocksDB, in-memory and changelog topics
---

# State backends: RocksDB, in-memory and changelog topics

*Streaming and distributed processing*

## Concept

State backends are the mechanisms that Flink and Kafka Streams use to persist intermediate computation results—joins, aggregations, windowed operations—so they survive failures and restarts. Without them, stateful operations lose their context: a running sum resets, a join forgets which records it has seen, and exactly-once semantics collapse. RocksDB is an embedded key-value store optimized for write-heavy workloads; in-memory backends store state only in RAM (fast but non-durable); changelog topics (compacted Kafka topics) record all state mutations, enabling state reconstruction and cross-cluster migration.

The choice matters most when stream processing jobs are long-running, handle high cardinality state (millions of unique keys), or must recover from failures without data loss. RocksDB trades throughput for durability and scales to terabytes per task; in-memory works for small, low-latency state that fits in heap; changelog topics decouple state storage from compute, allowing replaying and auditing state changes. Without choosing correctly, you either leak memory, lose state on restart, or create bottlenecks during recovery.

Think practically: a streaming join of job postings to candidate applications needs to remember which postings it has seen for minutes or hours. If the job crashes after processing 100k postings but before joining them, restarting with no state means duplicate or missed matches. RocksDB persists that join state locally; changelog topics persist it centrally so any replica can take over.

## Practice

**Problem:** You're building a streaming job that enriches job postings with a count of applications per job in the last 24 hours (via a tumbling window). The job must handle late-arriving records and recover correctly after a crash. Which state backend would you use and why? Write a pseudo-SQL representation of the state you need to maintain.

```sql
-- State schema for 24-hour application count per job
-- Conceptually maintained by the state backend:

CREATE TABLE job_application_state (
  job_id STRING,          -- key
  window_start TIMESTAMP, -- tumbling window boundary
  window_end TIMESTAMP,
  app_count BIGINT,       -- mutable aggregate
  watermark TIMESTAMP     -- latest event time seen
  PRIMARY KEY (job_id, window_start)
);

-- Recovery scenario:
-- If job crashes at 15:47, RocksDB retains this state locally.
-- Changelog topic (if enabled) has immutable record of all mutations:
--   {job_id: 42, window_start: 15:00, app_count: 1, ts: 15:01}
--   {job_id: 42, window_start: 15:00, app_count: 2, ts: 15:05}
--   {job_id: 42, window_start: 15:00, app_count: 3, ts: 15:10}
-- On restart, the last compacted snapshot is replayed first (fast), 
-- then changelog is applied up to the crash point.
```

## Notes

- **RocksDB tuning is critical**: default block cache is 8MB; for high-cardinality state, increase it and tune `db.block.cache.size` and compression. Watch disk I/O, not CPU.
- **Changelog topics add latency**: every state write becomes a Kafka write; use log compaction to keep topics bounded, but understand that compaction lag increases recovery time.
- **In-memory state is only safe for bursty, bounded problems**: if your key space grows unbounded (e.g., distinct user IDs arriving forever), you *will* OOM; use TTL (state expiration) religiously.
- **Exactly-once requires consistent snapshotting**: state backends must checkpoint atomically with input offsets; if checkpoint fails midway, rebalancing or restart replays duplicates—this is expected and deduplication logic (idempotent writes, dedup windows) must be application-level.
- **Adjacent: incremental checkpoints** reduce snapshot latency by storing only state deltas; **savepoints** are manual, versioned checkpoints for code upgrades; **state expiration (TTL)** prevents unbounded growth in windowed joins.
