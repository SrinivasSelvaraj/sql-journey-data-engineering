---
date: 2026-08-24
phase: cloud
topic: Managed Kafka alternatives: Kinesis, Pub/Sub, Event Hubs
---

# Managed Kafka alternatives: Kinesis, Pub/Sub, Event Hubs

*Cloud platforms and storage*

## Concept

Managed Kafka alternatives—AWS Kinesis, Google Cloud Pub/Sub, and Azure Event Hubs—are fully managed streaming services that replace the operational burden of running Kafka clusters. Unlike self-hosted Kafka, you pay for throughput (shards/partitions), storage retention, and API calls rather than compute instances, making costs predictable but potentially higher at scale. Each platform differs critically in ordering guarantees, latency, and cost model: Kinesis uses shards with per-shard pricing; Pub/Sub uses topics with publish/subscribe pricing; Event Hubs uses throughput units with time-based billing.

The choice matters when your pipeline needs low-latency ingestion (milliseconds), strict ordering within partitions, or multi-consumer replay—common in real-time analytics, event sourcing, or CDC from databases. Without the right platform, you either overpay for unused capacity, hit throughput limits during traffic spikes, or lose event ordering when you need it. Cost blowouts happen silently: a single runaway producer or consumer can multiply your bill 10x before you notice.

## Practice

**Problem:** You're ingesting job posting events to track salary trends in real-time. New job postings arrive at ~500/sec during business hours, with 10% spikes. You need to replay the last 7 days of events for backfill and support 3 independent consumer teams (analytics, ML, compliance). Which platform minimizes cost and prevents replay bottlenecks?

```sql
-- Kinesis: 500 msg/sec ÷ 1000 records/shard/sec = 0.5 shards minimum
-- With auto-scaling to handle 550 msg/sec peak: 1 shard = $0.36/day
-- 7-day retention = default, included
-- 3 consumers = 3 × (550 × 86400 × $0.014 per million) = ~$1.98/day
-- Pub/Sub: 500 msg/sec, $0.12 per GB ingested + $0.40 per GB egress per consumer
-- 1 day = 43.2 GB, 3 consumers = $1.29 ingress + $51.84 egress/day (TOO HIGH)
-- Event Hubs: 1 throughput unit = 1 MB/sec ingress, $0.015/hour = $0.36/day
-- Supports competitive consumer throughput, replay via Kafka protocol

SELECT 
  job_location,
  AVG(salary_year_avg) AS avg_salary,
  COUNT(*) AS job_count,
  DATE(job_posted_date) AS posted_date
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 7 DAY
  AND job_work_from_home = TRUE
GROUP BY job_location, posted_date
ORDER BY posted_date DESC, avg_salary DESC;
-- Consume from Kinesis stream in parallel: 1 consumer per shard avoids contention
```

## Notes

- **Kinesis pitfall:** Per-shard pricing means 10 shards = $3.60/day even idle; auto-scaling adds latency. Pub/Sub is cheaper for bursty, low-volume workloads; Kinesis wins at sustained high throughput.
- **Retention cost:** Kinesis includes 24 hours free, then $0.02 per shard-hour. Pub/Sub charges per GB stored. Event Hubs includes 1 day; older events require separate storage (blob/datalake).
- **Consumer scaling:** Kinesis and Event Hubs scale per shard/partition; Pub/Sub scales subscribers independently, risking egress bill explosion with many consumers.
- **Ordering guarantees:** Kinesis/Event Hubs preserve order per shard; Pub/Sub does not guarantee global order without custom logic—critical for compliance/audit streams.
- **Revisit:** Cost estimation requires load testing your real workload; use CloudWatch/Cloud Logging to baseline. Connect this to dead-letter queues (DLQ), consumer lag monitoring, and data warehouse staging costs.
