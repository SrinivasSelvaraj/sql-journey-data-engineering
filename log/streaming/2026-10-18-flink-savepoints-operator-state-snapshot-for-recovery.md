---
date: 2026-10-18
phase: streaming
topic: Flink savepoints: operator state snapshot for recovery
---

# Flink savepoints: operator state snapshot for recovery

*Streaming and distributed processing*

## Concept

A Flink savepoint is a consistent snapshot of an entire job's state—operator state, keyed state, and timers—written to durable storage at a specific point in time. When a job fails or needs to upgrade, you restore from a savepoint and resume exactly where you left off, preventing duplicate processing or data loss. Without savepoints, streaming jobs either lose in-flight computations or reprocess data unpredictably, breaking exactly-once semantics and corrupting aggregations.

Savepoints differ from checkpoints: checkpoints are automatic and frequent (used for recovery from crashes), while savepoints are explicit snapshots triggered by operators for controlled restarts. They're essential when your Flink job maintains state—counting events per user, tracking running balances, or windowing late-arriving records—because the operator's memory state evaporates on failure. Savepoints let you upgrade job logic, rescale parallelism, or rewind to a known good state without replaying the entire source.

## Practice

**Problem:** A Flink job processes job postings, aggregating the average salary per job title and per location. The job maintains a MapState storing running counts and sums. After 10 hours of processing, you need to deploy a code fix (changing the aggregation window from tumbling 1-hour to sliding 30-minute) without losing intermediate results or reprocessing all prior data.

```sql
-- Savepoint trigger (CLI command, not SQL):
-- flink savepoint <job_id> <target_directory>
-- Example:
-- flink savepoint 8a1e3f9d2c5b4e7a /flink/savepoints/job-20240115-143022

-- After the fix is deployed, restore from the savepoint:
-- flink run -s /flink/savepoints/job-20240115-143022 \
--   -c com.myorg.JobPostingAggregator \
--   job-posting-processor-v2.jar

-- The job resumes with all MapState intact:
-- salary_agg_by_title: {
--   "Data Engineer": {count: 4523, sum: 687450000},
--   "Product Manager": {count: 2891, sum: 521380000},
--   ...
-- }
-- salary_agg_by_location: {
--   "San Francisco, CA": {count: 8234, sum: 1234567000},
--   ...
-- }
-- Timers for pending window emissions are restored and fire on schedule.
```

## Notes

- **Savepoint size compounds quickly**: storing MapState with millions of keys + all operator state can produce multi-GB snapshots; monitor disk usage and consider state cleanup (TTL) to keep snapshots lean.
- **Parallelism rescaling requires matching operator UIDs**: if you change parallelism during restore, Flink needs unique operator IDs to map old state to new subtasks; use `.uid("my-operator")` in your DataStream API.
- **Exactly-once semantics depend on source idempotence**: savepoints recover operator state perfectly, but if your Kafka/Pulsar source lacks offset management or your sink lacks transactions, you'll still see duplicates; verify source and sink connectors support exactly-once.
- **Savepoints are not incremental by default**: each one is a full snapshot; checkpoint compression and RocksDB state backend incremental snapshots (for checkpoints) are separate concerns worth exploring for large state.
- **Test restore paths in dev/staging**: savepoint restore can fail silently if schemas change, serializers diverge, or paths are wrong; always validate restore works before a production outage forces it.
