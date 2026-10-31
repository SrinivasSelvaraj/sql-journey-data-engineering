---
date: 2026-10-31
phase: streaming
topic: Stateful processing and changelog optimization
---

# Stateful processing and changelog optimization

*Streaming and distributed processing*

## Concept

Stateful processing maintains accumulated context across streaming events—counts, aggregates, sessions, or deduplication state—without replaying the entire history. In a changelog-optimized system, you store only the *differences* (deletes and inserts of state changes) rather than full snapshots, dramatically reducing storage and I/O during recovery or state rebuild.

This matters when your stream processor crashes or scales horizontally: without a compact changelog, recovering state from raw events forces expensive recomputation. Changelog optimization trades write amplification (every state change creates a log entry) for faster reads and failover. It breaks spectacularly when you lose the changelog without a snapshot—you cannot reconstruct state—or when your changelog grows unbounded because you never compact it.

Real example: a fraud-detection job tracking user account balance and transaction count. Without stateful processing, you'd recalculate balances from scratch on every restart. Without changelog optimization, your state store bloats to gigabytes, and failover takes hours.

## Practice

**Problem:** You need to track the number of active job postings (posted within the last 30 days) per job_location, updating counts in real time as new postings arrive and old ones age out. A late-arriving posting from 45 days ago should *not* increment the count, and you must recover this state quickly after a failure.

```sql
-- Stateful aggregate with changelog optimization pattern
-- (pseudocode for Kafka Streams / Flink SQL)

CREATE TABLE active_jobs_state (
  job_location VARCHAR,
  count_active INT,
  last_updated TIMESTAMP(3),
  -- changelog stores: INSERT (new posting within window),
  -- DELETE (posting aged beyond 30 days), UPDATE (recount after retraction)
  PRIMARY KEY (job_location)
) WITH (
  'connector' = 'kafka',
  'topic' = 'active_jobs_state_changelog',
  'value.format' = 'json',
  'state.backend' = 'rocksdb',
  'state.checkpoints.dir' = 'file:///checkpoints'
);

-- Compute active postings per location (30-day window)
INSERT INTO active_jobs_state
SELECT 
  job_location,
  COUNT(DISTINCT job_id) AS count_active,
  CURRENT_TIMESTAMP AS last_updated
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30' DAY
GROUP BY job_location;

-- On recovery: state store replays *only* the changelog, 
-- not the entire job_postings_fact table.
```

## Notes

- **Changelog compaction is essential**: without periodic cleanup (e.g., Kafka log compaction, RocksDB compaction), your changelog itself becomes the bottleneck. Set compaction policies aggressively.
- **Exactly-once semantics depend on both state *and* changelog**: if you deduplicate at the processor but lose the changelog, you may reprocess events and double-count. Pair changelog optimization with idempotent writes or transactional outputs.
- **Late-arriving data vs. state eviction**: deciding *when* to remove old state (e.g., after 30 days) is a retention-vs-correctness tradeoff; document your grace period and TTL policies clearly.
- **Adjacent topics**: idempotency, snapshot strategies (periodic full state dumps for faster recovery), watermarking (how you handle out-of-order events), and state store backend choice (RocksDB, in-memory, external store like Redis).
- **Revisit**: practice designing changelog schemas that compress well (use deltas, not full rows); benchmark state recovery time after simulated failures.
