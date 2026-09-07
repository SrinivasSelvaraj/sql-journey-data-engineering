---
date: 2026-09-07
phase: streaming
topic: Backpressure: handling when consumer is slower than producer
---

# Backpressure: handling when consumer is slower than producer

*Streaming and distributed processing*

## Concept

Backpressure occurs when a data producer (source) emits events faster than a consumer (sink or downstream process) can process them. Without backpressure handling, unconsumed events accumulate in memory buffers, eventually causing the system to run out of memory, drop data silently, or crash. In streaming systems like Kafka, Flink, or even simple queue-based architectures, backpressure is the mechanism that signals "slow down, I can't keep up"—it prevents the producer from overwhelming downstream stages.

In practice, backpressure manifests as queue depth growing, latency increasing, or memory usage spiking. For example, if a job posting ingestion pipeline receives 10,000 events/sec but your analytics job can only process 2,000 events/sec, without backpressure the intermediate buffer will fill up within seconds. Most production systems handle this by pausing the producer, rejecting new messages with a "full" error, or applying rate-limiting and buffering strategies.

Ignoring backpressure is a common cause of data loss and system instability. Modern streaming frameworks (Kafka, Pulsar, RabbitMQ) have built-in backpressure support; traditional batch ETL tools often lack it, making incremental migration to streaming risky.

## Practice

**Problem:** A Kafka topic streams job postings at 5,000 msg/sec. Your SQL consumer aggregates job postings by location and salary tier every 10 seconds, but can only process 1,000 aggregations/sec. How do you prevent the Kafka consumer lag from growing unbounded?

```sql
-- Solution: Use windowed aggregation with explicit batching and commit frequency
-- Kafka consumer pulls in micro-batches, processes, then commits offset

WITH job_batch AS (
  -- Simulate 10-second tumbling window (Kafka consumer batches every 10s)
  SELECT
    job_location,
    CASE
      WHEN salary_year_avg < 60000 THEN 'entry_level'
      WHEN salary_year_avg < 120000 THEN 'mid_level'
      ELSE 'senior'
    END AS salary_tier,
    COUNT(*) AS posting_count,
    AVG(salary_year_avg) AS avg_salary,
    CURRENT_TIMESTAMP AS batch_window_start
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '10 seconds'
  GROUP BY job_location, salary_tier
)
INSERT INTO job_postings_agg (location, tier, count, avg_sal, window_ts, processed_at)
SELECT job_location, salary_tier, posting_count, avg_salary, batch_window_start, CURRENT_TIMESTAMP
FROM job_batch;

-- Separately: configure Kafka consumer with backpressure settings
-- fetch.max.bytes = 1MB (limit batch size)
-- fetch.min.bytes = 100KB (wait if fewer bytes available)
-- max.poll.records = 500 (pull max 500 msgs per poll, not 10k)
-- session.timeout.ms = 30000 (heartbeat if processing takes > 30s)
```

The key: limit `max.poll.records` and increase `session.timeout.ms` so the consumer pulls smaller batches and has time to process before the broker considers it dead. The producer naturally slows because the consumer doesn't keep pulling.

## Notes

- **Commit offset strategy matters:** commit *after* processing, not before. If you commit early and crash, you lose data; if you never commit, lag grows forever.
- **Queue depth is your canary:** monitor Kafka consumer lag, RabbitMQ queue length, or buffer fill %. When it starts climbing linearly, backpressure handling has failed.
- **Scaling vs. rejecting:** backpressure can be handled by scaling consumers (more partitions, more workers) or by explicitly rejecting/throttling the producer. Know which fits your SLA.
- **Confusing backpressure with flow control:** backpressure is about preventing overflow; flow control is about ordering and delivery guarantees. Both needed in streaming.
- **Revisit: idempotency and exactly-once semantics**—if you pause a producer mid-batch, restarting it requires idempotent message handling to avoid duplicates.
