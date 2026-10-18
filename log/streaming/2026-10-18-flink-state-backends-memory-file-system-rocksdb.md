---
date: 2026-10-18
phase: streaming
topic: Flink state backends: memory, file system, RocksDB
---

# Flink state backends: memory, file system, RocksDB

*Streaming and distributed processing*

## Concept

Flink state backends determine *where* and *how* operator state is stored during stream processing. State is any data an operator retains between events—counts, aggregates, session windows, keyed values. Without choosing a backend, your job either loses state on failure (memory-only) or becomes bottlenecked by I/O (file system). The backend choice directly affects latency, throughput, fault tolerance, and recovery time.

The three main backends trade off speed for durability. **MemoryStateBackend** keeps everything in the JVM heap: fast but lost on task failure unless checkpoints are enabled, and limited by available RAM. **FsStateBackend** writes state snapshots to distributed storage (HDFS, S3) but keeps the working copy in memory—good for medium state sizes. **RocksDB** uses an embedded key-value store on local disk, spilling to disk as needed: handles large state (terabytes) with fault tolerance, but adds CPU overhead for serialization and disk I/O.

Choosing wrong causes either out-of-memory crashes under load, recovery times measured in hours after failure, or unexplained latency spikes. Production jobs almost always use RocksDB when state grows unpredictably or must survive node failures reliably.

## Practice

**Problem:** You're building a real-time dashboard tracking average salary by job title over a 24-hour sliding window. Job postings arrive out of order and duplicates occasionally occur. You need to emit the running average every minute, handle reprocessing after failures, and expect millions of postings per day.

```sql
-- Flink SQL approach with RocksDB state backend
CREATE TABLE job_postings (
  job_id STRING,
  job_title_short STRING,
  salary_year_avg DECIMAL(10, 2),
  job_posted_date TIMESTAMP(3),
  WATERMARK FOR job_posted_date AS job_posted_date - INTERVAL '5' SECOND
) WITH (
  'connector' = 'kafka',
  'topic' = 'job_postings',
  'properties.bootstrap.servers' = 'localhost:9092'
);

-- Stateful aggregation: RocksDB stores the sum and count per title per window
SELECT 
  TUMBLE_START(job_posted_date, INTERVAL '1' MINUTE) AS window_start,
  job_title_short,
  COUNT(DISTINCT job_id) AS posting_count,
  AVG(salary_year_avg) AS avg_salary,
  MAX(salary_year_avg) AS max_salary
FROM job_postings
WHERE job_posted_date >= CURRENT_TIMESTAMP - INTERVAL '24' HOUR
GROUP BY 
  TUMBLE(job_posted_date, INTERVAL '1' MINUTE),
  job_title_short;

-- Configuration (in flink-conf.yaml or code):
-- state.backend: rocksdb
-- state.backend.rocksdb.local.dir: /var/flink/rocksdb
-- state.checkpoints.dir: s3://my-bucket/flink-checkpoints
-- state.backend.incremental: true
```

The RocksDB backend automatically manages state for each (title, window) pair. On failure, the last checkpoint restores state from S3 rather than reprocessing the entire 24 hours.

## Notes

- **Memory pressure trap:** MemoryStateBackend with large windows or high cardinality keys will crash mysteriously when state exceeds heap. RocksDB's disk spillover prevents this but requires monitoring disk usage and throughput.
- **Checkpoint tuning matters:** Even with RocksDB, slow or frequent checkpoints can stall pipelines. Incremental checkpoints (storing only deltas) and appropriate `checkpointInterval` are critical.
- **Serialization overhead:** RocksDB serializes to bytes on every read/write. Schema evolution and custom serializers can become bottlenecks; use Avro or Protobuf consistently.
- **State backend is per-job, not per-operator:** You choose one backend for the entire job at submission time. Different operators share the same backend.
- **Related: checkpoint alignment, savepoints, and TTL cleanup.** State without a cleanup policy (time-to-live) grows unbounded; manage this explicitly for windows and joins.
