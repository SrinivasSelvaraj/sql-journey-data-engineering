---
date: 2026-09-07
phase: streaming
topic: Burst traffic: buffering strategy and queue depth limits
---

# Burst traffic: buffering strategy and queue depth limits

*Streaming and distributed processing*

## Concept

Burst traffic occurs when data arrives in sudden waves rather than at a steady rate—common in real-time systems where job postings spike during business hours or when downstream systems recover from outages. Without buffering, these bursts overwhelm your processing pipeline: messages are dropped, backpressure cascades upstream, or services crash trying to allocate memory for queues that grow unbounded.

A buffering strategy defines *how deep* your queue can grow before you start rejecting or dropping data. Queue depth limits prevent runaway memory consumption and force explicit decisions: do you drop newest messages (tail drop), oldest messages (head drop), or apply priority-based selection? The choice depends on your use case—losing recent job postings might be acceptable, but losing high-salary roles is not.

Without limits, a burst lasting 2 minutes on a system designed for steady-state throughput can exhaust available memory in seconds. With limits, you trade latency (queued messages wait longer) for stability. You also gain visibility: when a queue fills, it signals that your consumer is slower than your producer, prompting scaling decisions.

## Practice

**Problem:** A job posting ingestion pipeline receives 100 postings/second on average, but recruitment campaigns create bursts of 500 postings/second for 30 seconds. Your Kafka consumer processes postings and writes to a fact table. During bursts, memory usage spikes and some postings are lost before reaching the database.

**Solution:** Implement queue depth limits and monitor lag:

```sql
-- Monitor queue depth and consumer lag
SELECT 
  topic,
  partition,
  log_end_offset - consumer_offset AS queue_depth,
  consumer_offset,
  CASE 
    WHEN log_end_offset - consumer_offset > 10000 THEN 'CRITICAL'
    WHEN log_end_offset - consumer_offset > 5000 THEN 'WARNING'
    ELSE 'HEALTHY'
  END AS queue_status,
  CURRENT_TIMESTAMP AS checked_at
FROM kafka_consumer_lag
WHERE topic = 'job_postings_raw'
ORDER BY queue_depth DESC;

-- Batch insert with backpressure: only commit if queue depth acceptable
INSERT INTO job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT 
  jp.job_id,
  jp.job_title_short,
  jp.salary_year_avg,
  jp.job_work_from_home,
  jp.job_posted_date,
  jp.job_location
FROM staging_job_postings jp
WHERE jp.ingestion_batch_id = CURRENT_BATCH_ID
  AND NOT EXISTS (
    SELECT 1 FROM job_postings_fact jpf 
    WHERE jpf.job_id = jp.job_id
  )
LIMIT 5000;  -- Buffer in-memory batch size; pause consumption if queue > threshold
```

## Notes

- **Common mistake:** Setting queue depth limits too low (under 1000 messages) causes throughput collapse during normal variation; too high (unbounded) causes OOM crashes. Tune based on message size and available memory: `max_queue_depth = available_memory / avg_message_size × 0.7`.
- **Backpressure coupling:** Queue depth limits only help if your consumer respects them. Implement explicit pause/resume signals; Kafka's `pause()` and `resume()` methods let consumers stop pulling when a downstream database is slow.
- **Relates to:** circuit breaker patterns (fail fast if queue exceeds threshold), rate limiting (reject producers before buffering), and auto-scaling (scale horizontally when lag exceeds SLA).
- **Priority vs. fairness:** For job postings, you might implement weighted queues: senior/high-salary roles get buffer slots before entry-level postings. Requires topic partitioning or a custom queue manager.
- **Revisit:** Dead-letter queues for messages that exceed retry limits, and how to measure actual queue depth in distributed systems where the buffer spans multiple brokers.
