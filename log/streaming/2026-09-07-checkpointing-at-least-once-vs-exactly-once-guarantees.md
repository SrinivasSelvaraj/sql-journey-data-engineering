---
date: 2026-09-07
phase: streaming
topic: Checkpointing: at-least-once vs exactly-once guarantees
---

# Checkpointing: at-least-once vs exactly-once guarantees

*Streaming and distributed processing*

## Concept

Checkpointing is the mechanism by which a streaming system records its progress—which data has been processed and in what state—so it can recover without losing or duplicating work. **At-least-once** means if a process fails after processing but before committing, that data will be reprocessed; you may see duplicates but no data loss. **Exactly-once** means each record is processed and counted once, even across failures; it requires coordinating checkpoints with output writes (often called "end-to-end exactly-once").

Without checkpointing, a streaming job crash means either starting from the beginning (reprocessing everything and inflating metrics) or starting from where you *think* you left off (silently skipping data). This matters acutely when aggregating—a counter restarted from zero, or an order that gets counted twice, corrupts your business logic. Exactly-once is harder: it requires idempotent writes (same input always produces same output) and distributed consensus on what "committed" means.

At-least-once is the practical default for most systems (Kafka, Spark Streaming, Flink default mode) because it's simpler and cheaper. Exactly-once is needed for financial transactions, inventory counts, or any metric that directly affects decisions or revenue.

## Practice

**Problem:** You are building a real-time aggregation of job postings by location and work-from-home status. Every minute, a Spark Streaming job reads from a Kafka topic and upserts into a summary table. If the job crashes mid-microbatch, you need to ensure salary averages and job counts stay correct.

```sql
-- Exactly-once solution: use a checkpoint-aware upsert with idempotent keys
-- Spark Structured Streaming with checkpoint directory specified

-- 1. Source: Kafka with offset tracking (Spark manages this via checkpoints)
val jobPostingsStream = spark
  .readStream
  .format("kafka")
  .option("kafka.bootstrap.servers", "localhost:9092")
  .option("subscribe", "job_postings")
  .load()

-- 2. Parse and aggregate
val parsed = jobPostingsStream
  .select(
    from_json(col("value").cast("string"), 
      StructType(/*job_postings_fact schema*/)).alias("data")
  )
  .select("data.*")

val agg = parsed
  .groupBy("job_location", "job_work_from_home")
  .agg(
    count("job_id").alias("job_count"),
    avg("salary_year_avg").alias("avg_salary"),
    max("job_posted_date").alias("latest_date")
  )

-- 3. Idempotent write with checkpoint
agg
  .writeStream
  .format("parquet") -- or Delta Lake for ACID
  .mode("append")
  .option("checkpointLocation", "/path/to/checkpoint")
  .option("path", "/path/to/output")
  .start()
  .awaitTermination()

-- For exactly-once with a mutable table, use Delta Lake:
agg
  .writeStream
  .format("delta")
  .mode("append")
  .option("checkpointLocation", "/path/to/checkpoint")
  .mergeSchema("true")
  .start("delta_table_uri")
  .awaitTermination()
```

The checkpoint directory stores Kafka offsets and query progress; Spark replays only unprocessed offsets on restart. Delta Lake ensures the merge is atomic.

## Notes

- **Checkpoint overhead:** Checkpoints are I/O-heavy; write them to durable storage (S3, HDFS, or managed object store) not local disk. Stale or corrupted checkpoints can cause reprocessing or data loss.
- **Idempotence is mandatory for exactly-once:** If your output write isn't idempotent (e.g., inserting into a table without a unique key constraint), you'll get duplicates despite checkpointing. Use MERGE, upsert keys, or immutable append-only logs.
- **Watermarking and late arrivals:** Checkpointing alone doesn't handle out-of-order data; combine it with event-time windows and watermarks to drop or buffer late events consistently.
- **State backend and consistency:** In Flink and similar systems, the state backend (in-memory, RocksDB, external store) must be checkpointed atomically with input offsets; mismatch causes inconsistency.
- **Cost vs. safety trade-off:** At-least-once is faster and cheaper; exactly-once adds latency and coordination cost. For analytics, at-least-once + idempotent downstream writes (e.g., Delta upsert) often suffices; for payments, demand end-to-end exactly-once.
