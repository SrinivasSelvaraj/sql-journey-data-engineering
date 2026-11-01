---
date: 2026-11-01
phase: streaming
topic: Checkpointing and state backend selection
---

# Checkpointing and state backend selection

*Streaming and distributed processing*

## Concept

Checkpointing is the mechanism that allows a streaming job to resume from exactly where it left off after failure, rather than reprocessing from the beginning or losing in-flight state. Without checkpointing, a crash mid-aggregation means either duplicate results (if you replay from the last message) or lost results (if you skip ahead). The state backend is the pluggable storage layer—memory, RocksDB, or external systems—where your job stores intermediate computation results like running sums, counts, or session windows.

In distributed streaming (Flink, Spark Structured Streaming, Kafka Streams), state explodes across partitions. A job aggregating salary_year_avg by job_location across 100 Kafka partitions holds 100 partial aggregates simultaneously. Checkpointing saves snapshots of all these states plus the position in each input partition, creating a consistent recovery point. Without it, you either lose hours of windowed aggregations or double-count rows.

State backend selection is a performance vs. durability tradeoff. In-memory backends are fast but disappear on restart. RocksDB spills to local disk (survives process crash, slower), while external backends (S3, DFS) survive machine failure but add latency. For critical jobs (financial aggregations), you accept higher latency for correctness; for analytics dashboards, you might tolerate occasional data loss for throughput.

## Practice

**Problem:** A Flink job aggregates salary_year_avg by job_location using a tumbling 1-hour window. After 3 hours of processing, the task manager crashes. Without checkpointing, the job loses all three windows' partial sums. Design a checkpointing strategy.

```sql
-- Pseudo-config (Flink Java/Scala pattern)
StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

// Enable checkpointing: snapshot every 60 seconds
env.enableCheckpointing(60000); // 60s interval
env.getCheckpointConfig().setCheckpointingMode(CheckpointingMode.EXACTLY_ONCE);
env.getCheckpointConfig().setMinPauseBetweenCheckpoints(30000);

// Use RocksDB for large state (survives task manager restart)
RocksDBStateBackend backend = new RocksDBStateBackend("s3://my-bucket/checkpoints");
backend.setIncremental(true); // Only diff from last checkpoint
env.setStateBackend(backend);

// Aggregate query
DataStream<Tuple2<String, Double>> salaryByLocation = jobPostings
  .keyBy(job -> job.job_location)
  .window(TumblingEventTimeWindows.of(Time.hours(1)))
  .aggregate(new AverageSalaryAggregator());

// On restart, Flink automatically restores state from checkpoint before crash,
// resumes from last watermark offset, avoids reprocessing or gaps
```

## Notes

- **RocksDB incremental checkpoints** save only state changes since the last snapshot, cutting checkpoint time from minutes to seconds on large jobs; essential for frequent checkpointing without blocking processing.
- **Exactly-once semantics require idempotent sinks** (deduplication on job_id + timestamp or writing to transactions); checkpointing guarantees the *job* sees each event once, but your sink must handle replayed writes gracefully.
- **Watermarks and checkpointing are coupled**; a late checkpoint holds back watermark advancement, delaying window closes and blocking downstream operators—monitor checkpoint duration religiously.
- **State size explosion** is common: a job grouping by job_location with no TTL can accumulate infinite states if locations are unique; use state TTL (e.g., discard state older than 7 days) to prevent OOM on long-running jobs.
- **Adjacent topics**: rescaling (changing parallelism) requires compatible state layout; read up on state redistribution and KeyGroup assignments when scaling from 10 to 100 partitions.
