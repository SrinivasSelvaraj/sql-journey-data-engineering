---
date: 2026-09-07
phase: streaming
topic: Savepoints for manual recovery and version upgrades
---

# Savepoints for manual recovery and version upgrades

*Streaming and distributed processing*

## Concept

Savepoints in streaming are named checkpoints that capture the complete state of a pipeline at a specific moment—input offsets, operator state, and side-effect markers. When a job crashes or you deploy a version upgrade, you resume from the savepoint rather than reprocessing all historical data or starting over. Without savepoints, every failure means data loss, duplicate writes, or backfills that waste compute. In distributed systems handling unordered, never-ending streams, savepoints are the only safe way to guarantee exactly-once semantics and idempotent recovery without manual intervention.

Savepoints differ from automatic checkpoints in that they're explicitly triggered (usually before maintenance) and can be named and retained long-term. They matter most when upgrading topology (adding new operators, changing parallelism), migrating state backends, or recovering from bugs that require code fixes. A failed job without savepoints forces you to either lose data from the crash window or replay everything—both unacceptable in production streaming.

## Practice

**Problem:** Your streaming job ingests job postings in real time and computes a 24-hour rolling average of `salary_year_avg` per `job_location`. After running for 3 days, you discover a bug: remote-work salaries are being filtered incorrectly. You need to fix the filter logic and resume without losing the 3-day state or reprocessing all postings.

```sql
-- Before upgrade: trigger explicit savepoint
SAVEPOINT sp_job_salary_rollup_v1;

-- Fix applied in new version: correct the remote-work filter
-- Logic change: WHERE job_work_from_home = FALSE should include remote roles correctly
SELECT 
  job_location,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary_24h,
  WINDOW_START
FROM job_postings_fact
WHERE 
  job_posted_date >= CURRENT_DATE - INTERVAL '24' HOUR
  AND job_location IS NOT NULL
GROUP BY job_location, WINDOW_START
EMIT CHANGES;

-- Resume job from savepoint
RESUME FROM SAVEPOINT sp_job_salary_rollup_v1;
```

## Notes

- **State backend alignment:** Savepoints are backend-specific (RocksDB, in-memory). Verify the restored job uses the same backend, or migration is required—mismatches silently corrupt state.
- **Operator ordering sensitivity:** Adding or removing stateful operators mid-stream breaks savepoint compatibility. Plan topology changes to be backward compatible or accept full replay.
- **Offset management:** Savepoints must capture input offsets (Kafka partitions, timestamps). If you lose the savepoint metadata file, you've lost recovery—store multiple copies and version them.
- **Clock skew in distributed systems:** Timestamp-based resumption assumes synchronized clocks; watermarks and allowed lateness windows interact with savepoint timing in subtle ways.
- **Adjacent: Exactly-once semantics, idempotent sinks, state TTL policies.** Savepoints alone don't guarantee correctness without idempotent writes downstream and proper handling of in-flight transactions.
