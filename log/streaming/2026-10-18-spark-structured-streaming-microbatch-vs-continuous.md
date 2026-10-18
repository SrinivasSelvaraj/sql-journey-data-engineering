---
date: 2026-10-18
phase: streaming
topic: Spark Structured Streaming: microbatch vs continuous
---

# Spark Structured Streaming: microbatch vs continuous

*Streaming and distributed processing*

## Concept

Spark Structured Streaming offers two execution modes: **microbatch** (default) and **continuous**. Microbatch groups arriving data into small batches processed at fixed intervals (e.g., every 1 second), while continuous processing treats each record individually with near-millisecond latency. Microbatch is stateful and fault-tolerant by design—Spark checkpoints progress and can replay lost batches; continuous mode sacrifices some durability guarantees for lower latency, making it suitable only for scenarios where occasional record loss is acceptable.

The choice matters when latency requirements conflict with fault tolerance. Microbatch shines in typical analytics: hourly salary aggregations, daily job posting counts, or maintaining slowly-changing dimensions where exact-once semantics and recovery are non-negotiable. Continuous mode breaks without explicit handling of exactly-once semantics and requires careful monitoring because a node failure may lose in-flight records that were never checkpointed.

## Practice

**Problem:** You're streaming job postings in real-time and need to compute the running count of remote-eligible jobs (job_work_from_home = true) grouped by job_title_short, updated every 5 seconds. You must not lose records and must be able to restart from the last checkpoint after failure.

```sql
-- Microbatch approach (recommended for this scenario)
df = spark.readStream \
  .format("kafka") \
  .option("kafka.bootstrap.servers", "broker:9092") \
  .option("subscribe", "job_postings") \
  .load()

parsed_df = df.select(
  from_json(col("value").cast("string"), 
    "job_id STRING, job_title_short STRING, salary_year_avg INT, job_work_from_home BOOLEAN, job_posted_date DATE, job_location STRING"
  ).alias("data")
).select("data.*")

remote_count = parsed_df \
  .filter(col("job_work_from_home") == True) \
  .groupBy("job_title_short") \
  .agg(count("job_id").alias("remote_job_count")) \
  .select("job_title_short", "remote_job_count")

query = remote_count.writeStream \
  .format("console") \
  .option("checkpointLocation", "/tmp/job_posts_checkpoint") \
  .trigger(processingTime="5 seconds") \
  .outputMode("update") \
  .start()

query.awaitTermination()
```

## Notes

- **Microbatch latency floor:** Even with 1-second triggers, you're waiting ~1–2 seconds end-to-end; don't expect sub-second freshness. Continuous mode achieves ~1ms but at the cost of exactly-once guarantees.
- **Checkpoint directory is critical:** Always set `checkpointLocation` for microbatch; losing it means losing offset state and you'll reprocess or skip data. Use distributed storage (S3, HDFS) in production, not local `/tmp`.
- **OutputMode matters:** Use `update` for aggregations (only changed rows), `append` for stateless filters, and `complete` sparingly (full output, expensive for large state).
- **Adjacent topics:** Watermarking (handling late data), state store management (for joins/aggregations), and Kafka offset management tie directly into choosing the right streaming mode.
- **Common mistake:** Switching to continuous mode to fix latency without testing recovery; a node crash will silently drop records. Microbatch + aggressive trigger timing is usually the right answer for analytics.
