---
date: 2026-11-01
phase: streaming
topic: Consumer lag monitoring and alerting
---

# Consumer lag monitoring and alerting

*Streaming and distributed processing*

## Concept

Consumer lag is the delta between the latest message offset produced to a topic and the offset a consumer group has processed. In streaming systems, lag measures how far behind real-time a consumer is running. High lag indicates a consumer cannot keep pace with producer throughput, leading to stale data in downstream systems, missed SLAs, and cascading failures when lag grows unbounded.

Lag monitoring matters most when you have fast producers, slow consumers, or both. A job posting ingestion pipeline might produce 1000 events/sec but your enrichment consumer only processes 500/sec—lag grows by 500 offsets per second. Without alerting, you discover the problem hours later when business reports show week-old data. At that point, backpressure is severe and recovery takes time.

Without lag visibility, you operate blind to system health. Consumers can fail silently, partition rebalancing can hide performance cliffs, and you cannot distinguish between "intentional backfill" and "the system is breaking." Lag thresholds (e.g., alert if lag > 10M messages or if lag grew >1M in 5 min) let you catch degradation early and scale consumers or producers before data staleness affects decisions.

## Practice

**Problem:** Your job_postings_fact data is consumed by two groups: a real-time dashboard and a nightly ML training job. The dashboard must never lag more than 5 minutes worth of events. The ML job can tolerate 12 hours of lag. Build a monitoring query that flags when each consumer group violates its SLA, using Kafka consumer lag metrics.

```sql
SELECT
  consumer_group,
  topic,
  partition,
  current_offset,
  log_end_offset,
  (log_end_offset - current_offset) AS lag_messages,
  CASE
    WHEN consumer_group = 'job-postings-dashboard'
      AND (log_end_offset - current_offset) > 5000 -- ~5 min at typical rate
      THEN 'ALERT: Dashboard lag SLA breached'
    WHEN consumer_group = 'job-postings-ml-train'
      AND (log_end_offset - current_offset) > 1000000 -- ~12 hours
      THEN 'ALERT: ML training lag SLA breached'
    ELSE 'OK'
  END AS sla_status,
  CURRENT_TIMESTAMP AS check_time
FROM kafka_consumer_lag
WHERE topic = 'job-postings-fact'
ORDER BY lag_messages DESC;
```

## Notes

- **Lag is per-partition, not global.** A topic with 10 partitions can have one lagging partition while others are caught up. Always aggregate thoughtfully or alert on p99 lag, not just max.
- **Distinguish lag from latency.** Lag is offset distance; latency is wall-clock delay from produce to consume. You need both metrics—a consumer can have low lag but high latency if processing is CPU-bound.
- **Watch lag growth rate, not just absolute value.** A consumer at 50M lag that stays flat is stable; one at 1M lag that grows 10M/hour is failing. Set alerts on rate of change to catch problems before they saturate your topic retention.
- **Consumer group rebalancing kills lag visibility.** During rebalancing, offset commits pause and lag spikes artificially. Filter out or expect noise during deployments; use a 2–3 rebalance window before raising alarms.
- **Connects to:** backpressure handling, partition key design (uneven lag suggests skewed keys), retention policy tuning (if lag approaches retention window, data is lost), and autoscaling logic (lag is the signal that drives consumer scaling decisions).
