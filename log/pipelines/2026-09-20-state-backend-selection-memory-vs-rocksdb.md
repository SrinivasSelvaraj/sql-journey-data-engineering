---
date: 2026-09-20
phase: pipelines
topic: State backend selection: memory vs RocksDB
---

# State backend selection: memory vs RocksDB

*Pipelines and orchestration*

## Concept

State backends in Flink (and similar streaming systems) persist operator state to disk, enabling recovery after failures. The two main options trade off speed for scale: **memory backends** keep all state in JVM heap—fast but limited to available RAM and lost on restart—while **RocksDB** spills to local disk, supporting terabyte-scale state with automatic checkpointing. Choose memory for low-latency, stateless-heavy jobs or dev environments; choose RocksDB for production jobs with large windows, joins across hours of data, or deduplication keyed on millions of unique values.

Without proper state backend selection, jobs either crash under load (memory fills up) or fail to recover from transient errors (state lost). A stream deduplicating events by user_id over 24 hours with millions of active users *must* use RocksDB; a memory backend will exhaust heap and the job dies without recovery. Conversely, a low-volume enrichment job using only millisecond-scale state wastes I/O overhead with RocksDB.

State backend choice directly impacts "rerun safely"—RocksDB's persistent checkpoints let you replay from the last consistent point, while memory state is gone the moment the container restarts.

## Practice

**Problem:** A job aggregates job posting salary data per job_title_short over sliding 7-day windows, counting occurrences and averaging salary_year_avg. During testing, the job processes 500k events/second and crashes after 2 hours with OutOfMemoryError.

**Solution:** Switch from in-memory state to RocksDB backend and configure incremental checkpointing:

```sql
-- Not a SQL solution, but the Flink job configuration:
StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

// Enable RocksDB backend with incremental checkpoints
env.setStateBackend(new EmbeddedRocksDBStateBackend());
env.getCheckpointConfig().setCheckpointingMode(CheckpointingMode.EXACTLY_ONCE);
env.getCheckpointConfig().setCheckpointInterval(60000); // 60s intervals

DataStream<JobPosting> postings = env.addSource(kafkaSource);

postings
  .keyBy(JobPosting::getJobTitleShort)
  .window(SlidingEventTimeWindows.of(Time.days(7), Time.days(1)))
  .aggregate(new SalaryAggregator())
  .addSink(resultSink);
```

RocksDB now handles the 7-day window state (~500k events/s × 7 days × metadata overhead) on disk instead of heap, and incremental checkpoints only write changed state, reducing I/O.

## Notes

- **Memory backend ≠ no durability:** even in-memory state gets checkpointed to distributed storage (HDFS/S3), but the *running* job keeps it in heap; recovery still works but is slower than RocksDB's warm start.
- **RocksDB overhead:** adds ~5–15% latency vs memory due to serialization and disk I/O; measure before assuming it's unacceptable for low-latency use cases.
- **Checkpoint vs savepoint:** RocksDB backends benefit most from frequent *checkpoints* (automatic recovery) paired with occasional *savepoints* (manual snapshots for code deploys).
- **Adjacent topics:** connects to windowing strategy (larger windows → bigger state → RocksDB mandatory), exactly-once semantics (requires persistent backend), and Kafka offset commit (decouple from state backend choice).
- **Common mistake:** leaving memory backend in production for "simplicity," then blaming the framework when a 6-hour outage loses state; RocksDB is the production default for good reason.
