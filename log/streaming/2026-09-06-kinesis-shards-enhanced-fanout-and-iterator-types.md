---
date: 2026-09-06
phase: streaming
topic: Kinesis: shards, enhanced fanout and iterator types
---

# Kinesis: shards, enhanced fanout and iterator types

*Streaming and distributed processing*

## Concept

AWS Kinesis is a managed streaming service where data flows into **shards**—partitions that each handle up to 1 MB/sec of writes and 2 MB/sec of reads. Each record gets a shard key (e.g., `job_id` or `job_location`) that determines which shard receives it; uneven distribution causes hot shards and throttling. **Enhanced Fanout** creates dedicated throughput pipes per consumer, so one slow reader doesn't starve others—critical when multiple teams consume the same stream at different rates.

**Iterator types** control where a consumer starts reading: `TRIM_HORIZON` begins at the oldest record (useful for backfill or replay), `LATEST` skips to new data only (good for real-time dashboards), and `AT_TIMESTAMP` resumes from a specific point (essential for exactly-once semantics after failure). Without choosing correctly, you either reprocess old data or miss critical events.

These three pieces interlock: shard count must match your throughput, fanout prevents consumer bottlenecks, and iterators ensure you don't lose position during failures or scale changes.

## Practice

**Problem:** A job-posting analytics team ingests 500 postings/sec keyed by `job_location`. One consumer builds a real-time dashboard (needs only *new* postings), another runs a nightly aggregation job (must not miss any data after restarts). The dashboard consumer is slow and blocks the aggregation consumer's reads. Design the stream setup.

```sql
-- Kinesis stream setup (pseudo-config, not SQL but conceptually):
-- Stream: job_postings_stream
-- Shard count: 10 (500 postings/sec ÷ 50 postings/sec per shard buffer)
-- Partition key: job_location (spreads load across regions)
-- Enhanced Fanout: ENABLED (isolates dashboard and aggregation consumers)

-- Dashboard consumer:
-- Iterator type: LATEST
-- Starts only from new data, ignores backlog

-- Aggregation consumer:
-- Iterator type: TRIM_HORIZON (first run) or AT_TIMESTAMP (resume from checkpointed time)
-- Checkpoints its shard iterator after each batch to handle failures
-- Stores offset in DynamoDB: (stream_name, shard_id, last_sequence_number, timestamp)

SELECT job_id, job_title_short, salary_year_avg, job_location, COUNT(*) as postings_count
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE
  AND job_work_from_home = TRUE
GROUP BY job_location, job_title_short
ORDER BY postings_count DESC;
```

## Notes

- **Hot shard trap:** Using a low-cardinality partition key (e.g., `job_work_from_home` with only 2 values) will concentrate traffic on one or two shards; always partition by high-cardinality fields like `job_location` or `job_id`.
- **Enhanced Fanout cost:** Each consumer with fanout enabled incurs per-hour charges; use standard (on-demand) consumers for one or two readers, fanout only when you have 3+ or throughput competition.
- **Iterator state management:** Store shard iterators *and* sequence numbers in an external store (DynamoDB, S3); Kinesis doesn't guarantee iterator lifetime beyond 15 minutes, and you need recovery checkpoints.
- **Connects to:** Kafka (alternative with different partition model), Lambda triggers on Kinesis (invoke functions per record batch), and DynamoDB Streams (similar fanout/shard model for table changes).
- **Revisit:** Test shard autoscaling behavior and understand how resharding affects iterator position; write a small Kinesis producer to stress-test your shard count estimate before production load.
