---
date: 2026-10-17
phase: streaming
topic: Backpressure: handling upstream faster than downstream
---

# Backpressure: handling upstream faster than downstream

*Streaming and distributed processing*

## Concept

Backpressure occurs when an upstream producer generates data faster than a downstream consumer can process it. Without backpressure handling, data accumulates in memory buffers, causing queue overflow, latency spikes, or complete system failure. In streaming systems, this is critical because data arrival is unbounded—you cannot simply "wait for all data" as you would in batch processing.

Backpressure mechanisms signal the producer to slow down, drop messages, or redirect them to a dead-letter queue. Common strategies include rate limiting, buffering with bounded queues, and applying back-off algorithms. Without these controls, a fast data source (e.g., a Kafka topic receiving millions of events per second) can overwhelm a slower sink (e.g., a database write bottleneck), causing cascading failures across the pipeline.

In practice, streaming frameworks like Apache Flink and Kafka Streams handle backpressure automatically by pausing consumption from upstream topics when buffers fill. However, you must still design sinks with explicit throughput limits, monitor queue depths, and set appropriate batch sizes and timeouts to prevent resource exhaustion.

## Practice

**Problem:** A job posting ingestion pipeline receives postings from multiple job boards at a combined rate of 50,000 events/second, but your downstream warehouse can only accept 5,000 inserts per second due to foreign key constraint validation. Messages are lost if not processed within 60 seconds.

**Solution:**

```sql
-- Consumer-side: Use a bounded queue with explicit batch windowing
WITH buffered_postings AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    ROW_NUMBER() OVER (ORDER BY job_posted_date ASC) AS seq,
    CURRENT_TIMESTAMP AS enqueued_at
  FROM kafka_topic_job_postings
  WHERE enqueued_at > CURRENT_TIMESTAMP - INTERVAL '60 seconds'
),
batched AS (
  SELECT
    *,
    FLOOR((seq - 1) / 5000) AS batch_id,
    FLOOR((seq - 1) / 5000) * 200 AS delay_ms  -- 200ms per batch
  FROM buffered_postings
)
INSERT INTO job_postings_fact
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM batched
ORDER BY batch_id, seq;

-- Dead-letter handling: route dropped messages
INSERT INTO job_postings_dead_letter
SELECT *, 'backpressure_timeout' AS drop_reason, CURRENT_TIMESTAMP AS dropped_at
FROM kafka_topic_job_postings
WHERE CURRENT_TIMESTAMP - enqueued_at > INTERVAL '60 seconds';
```

## Notes

- **Buffer sizing mistake:** Setting buffers too large masks backpressure signals and delays failure detection; too small causes premature drops. Start with 10–100× your batch size.
- **Monitoring blind spots:** Track queue depth and consumer lag separately—high lag without full queues indicates slow processing, not backpressure.
- **Connects to:** Circuit breakers (fail fast when downstream is unavailable), flow control protocols (e.g., TCP window size), and consumer group rebalancing in Kafka.
- **Idempotency prerequisite:** Backpressure often involves retries and deduplication; ensure sink operations are idempotent (e.g., `INSERT INTO ... ON CONFLICT DO NOTHING`).
- **Revisit when:** Adding sinks with different throughput capacities, or when moving from single-threaded to parallel consumers.
