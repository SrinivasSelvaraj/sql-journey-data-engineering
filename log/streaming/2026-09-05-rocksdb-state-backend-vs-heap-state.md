---
date: 2026-09-05
phase: streaming
topic: RocksDB state backend vs heap state
---

# RocksDB state backend vs heap state

*Streaming and distributed processing*

## Concept

**Heap state** stores all streaming state (windows, aggregations, join buffers) in JVM memory. It's fast and simple but limited by available RAM and causes full garbage collection pauses when state grows large. For a Flink job aggregating job postings by location over a 24-hour window, heap state works fine with hundreds of unique locations, but fails catastrophically at millions of locations—the JVM will eventually run out of memory or pause for 30+ seconds during GC.

**RocksDB state backend** spills state to local disk (embedded LSM tree), keeping only a working set in memory. It scales to terabytes of state and avoids full GC pauses. The tradeoff is I/O latency: RocksDB reads are 10–100× slower than heap access, but still sub-millisecond for typical streaming workloads. Choose RocksDB whenever state cardinality is unbounded or unpredictable—join state in production jobs almost always needs it.

State backend choice becomes critical in windowed aggregations over high-cardinality dimensions. With heap state, a 1-hour window over 10M unique job locations will either crash or pause the entire pipeline. RocksDB lets the pipeline run smoothly, trading microseconds of latency for stability at scale.

## Practice

**Problem:** A streaming job must count job postings per `job_location` over a 1-hour tumbling window, processing 100k events/sec. Job locations are unbounded and highly skewed (top 100 cities have 60% of postings, but tail reaches millions of unique values). Heap state will OOM within minutes. Design the state backend and aggregation.

```sql
-- Flink SQL DDL (conceptual)
CREATE TABLE job_postings_stream (
  job_id BIGINT,
  job_title_short STRING,
  job_location STRING,
  job_posted_date TIMESTAMP(3),
  WATERMARK FOR job_posted_date AS job_posted_date - INTERVAL '5' SECOND
) WITH (
  'connector' = 'kafka',
  'topic' = 'job_postings',
  'value.format' = 'json'
);

-- Solution: RocksDB backend + windowed aggregation
SELECT 
  TUMBLE_START(job_posted_date, INTERVAL '1' HOUR) AS window_start,
  job_location,
  COUNT(*) AS posting_count
FROM job_postings_stream
GROUP BY TUMBLE(job_posted_date, INTERVAL '1' HOUR), job_location;

-- Backend config (Java/Scala):
-- env.setStateBackend(new RocksDBStateBackend("s3://bucket/checkpoints", true))
-- env.getCheckpointConfig().setCheckpointingMode(CheckpointingMode.EXACTLY_ONCE)
```

The RocksDB backend with incremental checkpointing handles unbounded location cardinality without memory pressure, while the 5-second watermark allows late-arriving postings to correctly attribute to windows.

## Notes

- **Common mistake:** Assuming heap state is fine "for now" and deferring RocksDB. In production, cardinality grows unexpectedly; migrate under load is painful.
- **State size monitoring:** Always track `operator_state_size` metrics. Heap state >2GB is a warning sign; RocksDB >50GB is manageable.
- **Incremental checkpoints:** RocksDB shines with `enableIncrementalCheckpointing(true)`—only delta state is uploaded, reducing S3/HDFS traffic 10–50×.
- **Adjacent topic:** TTL state cleanup (`StateTtlConfig`) is orthogonal but essential—prevents unbounded growth in join/aggregate scenarios.
- **Revisit:** Compare RocksDB to remote state stores (Redis, DynamoDB) when latency SLA <10ms or state must be queried from outside the pipeline.
