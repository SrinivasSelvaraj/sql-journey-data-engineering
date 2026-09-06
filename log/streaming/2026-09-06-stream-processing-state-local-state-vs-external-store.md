---
date: 2026-09-06
phase: streaming
topic: Stream processing state: local state vs external store
---

# Stream processing state: local state vs external store

*Streaming and distributed processing*

## Concept

Stream processors must maintain state—data that persists across events—to compute meaningful results. **Local state** lives in the processor's memory (or local disk), making operations fast but vulnerable to failure; **external state** lives in a remote database or key-value store, making it durable but introducing latency and consistency challenges.

The choice matters because stateful operations like aggregations (total salary by job title), deduplication (seen job IDs), and windowed joins (match jobs to candidates within time bounds) require remembering prior events. Without state, each event is processed in isolation and you lose context. Local state fails silently when the stream processor crashes—you must rebuild it or lose work. External state survives crashes but can become a bottleneck if every event requires a round-trip query.

In practice: use local state for high-throughput, fault-tolerant systems with acceptable rebuild time (e.g., counting job postings per location within a tumbling window). Use external state for correctness guarantees across restarts, shared state across multiple stream jobs, or data that changes slowly (e.g., current job market rates fetched from a reference table).

## Practice

**Problem:** You need to track the *cumulative count of jobs posted per location* and emit an alert whenever a location exceeds 500 postings in a day. The stream processor may restart; you cannot lose the count.

```sql
-- External state: store running counts in a durable table
CREATE TABLE job_posting_counts (
  job_location VARCHAR,
  posting_date DATE,
  count_posted INT,
  PRIMARY KEY (job_location, posting_date)
);

-- Stream query: on each event, upsert the count
INSERT INTO job_posting_counts (job_location, posting_date, count_posted)
SELECT job_location, job_posted_date, COUNT(*) AS count_posted
FROM job_postings_fact
GROUP BY job_location, job_posted_date
ON CONFLICT (job_location, posting_date)
  DO UPDATE SET count_posted = job_posting_counts.count_posted + EXCLUDED.count_posted;

-- Alert logic: join stream to external counts
SELECT jp.job_location, jpc.count_posted
FROM job_postings_fact jp
JOIN job_posting_counts jpc 
  ON jp.job_location = jpc.job_location 
  AND jp.job_posted_date = jpc.posting_date
WHERE jpc.count_posted > 500;
```

## Notes

- **Exactly-once semantics matter**: idempotent writes and deduplication logic prevent double-counting when a stream processor restarts mid-batch. Upserts on a primary key help, but clock skew and late arrivals can still cause drift.
- **State size growth**: local state can consume unbounded memory if not windowed or TTL'd. External stores shift the cost but introduce network overhead and require careful partitioning to avoid hot keys.
- **Consistency models**: local state is eventually consistent with the event stream but not with other jobs; external state is consistent across jobs but slower. RocksDB (local) + changelog topics (recovery) is a hybrid pattern.
- **Adjacent topics**: windowing (time-based state boundaries), watermarks (knowing when state is "complete"), and changelogs (Kafka topics that replay state on recovery).
- **Revisit**: when stream jobs share state, single-writer principle (one job owns a fact table) prevents race conditions better than distributed locking.
