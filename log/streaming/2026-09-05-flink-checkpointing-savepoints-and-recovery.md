---
date: 2026-09-05
phase: streaming
topic: Flink checkpointing, savepoints and recovery
---

# Flink checkpointing, savepoints and recovery

*Streaming and distributed processing*

## Concept

Flink's checkpoint mechanism periodically captures the entire state of a streaming job—operator state, window buffers, timers—creating an atomic snapshot that enables exactly-once processing semantics. Checkpoints are triggered automatically at configurable intervals and happen *asynchronously* while the job continues running, meaning they don't block data processing. Without checkpointing, any failure (node crash, network partition, deployment update) forces a job restart from the beginning, losing all in-flight computations and violating ordering guarantees.

Savepoints differ from checkpoints: they're *manually triggered*, externally stored, and versioned for intentional pauses, code upgrades, or job migration. A checkpoint is for automatic recovery; a savepoint is for controlled state management. In production, both matter equally—checkpoints handle surprise failures, savepoints handle planned maintenance. Without them, distributed streaming becomes unreliable for stateful operations like aggregations, joins, or deduplication.

## Practice

**Problem:** You're running a Flink job that counts job postings by location per day, and you need to recover mid-day aggregations if the job crashes. Without recovery, you'd lose counts for partially processed days.

```sql
-- Conceptual Flink streaming job (pseudo-SQL with Flink semantics)
-- This shows what state needs checkpointing

SELECT 
  job_location,
  CAST(job_posted_date AS DATE) AS post_date,
  COUNT(*) AS posting_count,
  AVG(salary_year_avg) AS avg_salary
FROM job_postings_fact
GROUP BY 
  job_location,
  CAST(job_posted_date AS DATE)
EMIT RESULTS EVERY 1 MINUTE;

-- Configuration for checkpoint safety:
-- execution.checkpointing.mode: EXACTLY_ONCE
-- execution.checkpointing.interval: 60000 (1 min)
-- state.backend: rocksdb
-- state.checkpoints.dir: s3://my-bucket/flink-checkpoints/
```

Without checkpointing enabled, a 10-minute crash mid-aggregation means losing all GROUP BY state. With `EXACTLY_ONCE` mode and RocksDB state backend, Flink restores the partial window state and continues from the last checkpoint, preserving count accuracy.

## Notes

- **Common mistake:** assuming checkpoints are free; they incur I/O latency and state size grows with window cardinality. Monitor checkpoint duration and size metrics in production.
- **Savepoint vs. checkpoint confusion:** checkpoints are automatic safety nets; savepoints are versioned backups for controlled operations like schema evolution or operator reordering.
- **State backend choice matters:** in-memory (limited scale), RocksDB (large state, slower), external stores (separate infra cost). For production jobs with hours-long windows, RocksDB is standard.
- **Connects to:** watermarks (checkpoints freeze watermark progress), event-time semantics (out-of-order data recovery depends on state), and idempotent sinks (exactly-once *processing* doesn't guarantee exactly-once *output* without idempotent writes).
- **Revisit:** unaligned checkpoints (Flink 1.15+) reduce backpressure by not draining in-flight buffers, but complicate debugging; weigh latency vs. observability for your SLA.
