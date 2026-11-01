---
date: 2026-11-01
phase: streaming
topic: Flink job savepoints and recovery
---

# Flink job savepoints and recovery

*Streaming and distributed processing*

## Concept

A Flink savepoint is a consistent snapshot of an entire job's state at a point in time—operator state, keyed state, and window buffers all frozen together. When a job crashes, you restart from the savepoint rather than from the beginning, resuming exactly where it left off without reprocessing or losing in-flight data. This matters because streaming jobs often run 24/7 processing unbounded data; without savepoints, a crash means either data loss or massive reprocessing overhead.

Savepoints differ from checkpoints: checkpoints are automatic, frequent, and internal; savepoints are manual, explicit snapshots you trigger before upgrades, code changes, or maintenance. Without savepoints, you face a hard choice—lose recent state or replay hours of data. With savepoints, you can safely stop a job, modify its logic, and resume from the exact same position in the stream.

The critical detail: savepoint recovery only works if your state is self-contained and your source connector can be rewound (e.g., Kafka with stored offsets, not a TCP stream). Stateless transformations don't need savepoints; stateful aggregations and joins absolutely do.

## Practice

**Problem:** A job continuously aggregates job postings by location, maintaining a count of open positions per city and a running average salary. After 3 days of processing, the job crashes. You need to recover without losing counts or reprocessing all 3 days of events.

```sql
-- Job logic (pseudo-Flink SQL/DataStream)
-- Source: job_postings_fact from Kafka (offset-tracked)
-- Keyed state: job_location → (count, sum_salary, window_state)

SELECT 
  job_location,
  COUNT(*) as open_positions,
  AVG(salary_year_avg) as avg_salary,
  TUMBLE_END(job_posted_date, INTERVAL '1' DAY) as day_bucket
FROM job_postings_fact
WHERE job_work_from_home = FALSE
GROUP BY job_location, TUMBLE(job_posted_date, INTERVAL '1' DAY)

-- Before maintenance/upgrade:
-- flink run -s /checkpoints/savepoint-2024-01-15-001 job.jar
-- This saves keyed state (location aggregates) to distributed storage

-- After restart:
-- flink run -s /checkpoints/savepoint-2024-01-15-001 job.jar
-- Job resumes from Kafka offset stored in savepoint, no data loss
```

## Notes

- **State backend matters:** RocksDB for large state, in-memory for small state. Savepoint portability depends on backend choice; mixing backends across restarts can cause deserialization failures.
- **Offset management:** Savepoints store Kafka offsets or equivalent source positions. If you delete old Kafka messages before restoring, the job cannot rewind and will either fail or jump to the earliest available offset.
- **Versioning and schema evolution:** Changing operator logic or state types between savepoint and restore risks serialization errors. Use explicit state serializers and versioning when evolving jobs.
- **Adjacent topics:** Checkpoints (automatic durability), external state (Redis/database for cross-job state sharing), idempotence (ensuring replayed events don't double-count).
- **Gotcha:** Removing a stateful operator from a job before restoring from a savepoint can cause deserialization to fail. Always drain old savepoints or manually migrate state if topology changes significantly.
