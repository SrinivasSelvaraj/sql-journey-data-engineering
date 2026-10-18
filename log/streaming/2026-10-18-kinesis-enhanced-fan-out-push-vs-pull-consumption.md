---
date: 2026-10-18
phase: streaming
topic: Kinesis enhanced fan-out: push vs pull consumption
---

# Kinesis enhanced fan-out: push vs pull consumption

*Streaming and distributed processing*

## Concept

Kinesis enhanced fan-out (EFO) enables *push*-based consumption where the stream pushes records directly to consumers at up to 2 MB/sec per shard, replacing the default *pull* model where consumers poll GetRecords. Without EFO, all consumers on a shard share a single 2 MB/sec quota, causing throughput contention and increased latency as consumer count grows. This matters when you have multiple independent applications consuming the same stream (e.g., real-time analytics, fraud detection, and warehouse sync all reading from a jobs posting stream) or when a single consumer needs high throughput with low latency.

EFO uses HTTP/2 server push to deliver records immediately as they arrive, eliminating the polling loop overhead and reducing end-to-end latency from seconds to milliseconds. The trade-off is cost: EFO charges per shard-hour plus per-request fees, whereas pull-based GetRecords scales with request volume. Choose EFO when latency sensitivity or multi-consumer isolation outweighs cost; choose pull when you have few consumers or can tolerate 200–1000ms delays and want predictable billing.

## Practice

**Problem:** You're building three independent Kinesis consumers for job_postings_fact: one ingests into Elasticsearch (100 rps), another triggers ML model inference (50 rps), and a third writes to S3 for warehouse sync (200 rps). Without EFO, all three compete for 2 MB/sec on a single shard, causing the ML pipeline to lag 5–10 seconds behind. Design the consumption strategy.

```sql
-- Enable EFO subscriptions for each consumer application
-- Consumer 1: Real-time search indexing
aws kinesis subscribe-to-shard \
  --stream-name job_postings_stream \
  --shard-id shardId-000000000000 \
  --consumer-arn arn:aws:kinesis:us-east-1:123456789012:stream/job_postings_stream/consumer/elasticsearch-consumer

-- Consumer 2: ML inference pipeline (lowest tolerance for latency)
aws kinesis subscribe-to-shard \
  --stream-name job_postings_stream \
  --shard-id shardId-000000000000 \
  --consumer-arn arn:aws:kinesis:us-east-1:123456789012:stream/job_postings_stream/consumer/ml-inference-consumer

-- Consumer 3: Warehouse sync (can tolerate slight delay, highest volume)
aws kinesis subscribe-to-shard \
  --stream-name job_postings_stream \
  --shard-id shardId-000000000000 \
  --consumer-arn arn:aws:kinesis:us-east-1:123456789012:stream/job_postings_stream/consumer/warehouse-sync-consumer

-- Each consumer now receives dedicated 2 MB/sec; no contention
-- Latency drops from 5–10s to ~50–100ms across all three pipelines
```

## Notes

- **Polling loops are invisible killers:** Default GetRecords with 1-second intervals adds guaranteed latency; pull feels cheaper upfront but compounds coordinator overhead across many consumers.
- **EFO is per consumer, not per shard:** Register a named consumer via RegisterStreamConsumer first; different apps reading the same shard each get 2 MB/sec isolation.
- **Cost modeling: break-even point ~3 consumers.** If you have fewer, pull is cheaper; if you have more, EFO's per-request cost pays for itself via reduced over-provisioning and faster time-to-insight.
- **Adjacent: DynamoDB streams also support EFO.** Apply same reasoning when multiple lambdas consume a single table's CDC stream—EFO prevents one aggressive processor from starving others.
- **Revisit: shard splitting and consumer group balancing.** EFO doesn't auto-scale shard assignment; you still need logic to handle when a shard splits or a consumer dies (use enhanced monitoring + CloudWatch alarms on iterator age).
