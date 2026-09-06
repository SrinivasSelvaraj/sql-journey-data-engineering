---
date: 2026-09-06
phase: streaming
topic: Monitoring Kafka: consumer lag and partition health
---

# Monitoring Kafka: consumer lag and partition health

*Streaming and distributed processing*

## Concept

Consumer lag measures how far behind a consumer group is from the latest message in a Kafka topic—the difference between the latest offset available in a partition and the offset the consumer has committed. High lag signals that messages are accumulating faster than the consumer can process them, which in streaming pipelines means stale data, delayed decisions, and potential data loss if retention is exceeded. Partition health (replication factor, in-sync replicas, leader availability) determines resilience; a partition with only one in-sync replica or no leader cannot accept writes and will cause producers to block or fail.

Without monitoring lag, you ship data to a data warehouse that lags production by hours, query results become unreliable, and you won't detect slow consumers or cascading backlog until users complain. Without partition health monitoring, a broker failure silently degrades your cluster: writes slow, reads become inconsistent, and recovery becomes opaque. These are invisible failures in streaming—the pipeline keeps running but produces stale or incomplete data.

Lag should be monitored per consumer group per partition (not just aggregate), because uneven lag across partitions often indicates skewed key distribution or slow downstream processing. Alert on lag velocity (rate of increase), not just absolute lag, so you catch problems before they become critical.

## Practice

**Problem:** The `job_postings_fact` table is consumed from a Kafka topic by a real-time ingestion job. The pipeline has been running for days, and you need to detect whether the ingestion is keeping up with arrival rate and whether any partition is at risk.

```sql
-- Monitor consumer lag per partition
SELECT
  consumer_group,
  topic,
  partition_id,
  committed_offset,
  latest_offset,
  (latest_offset - committed_offset) AS lag_messages,
  CASE 
    WHEN (latest_offset - committed_offset) > 100000 THEN 'CRITICAL'
    WHEN (latest_offset - committed_offset) > 10000 THEN 'WARNING'
    ELSE 'HEALTHY'
  END AS lag_status,
  CURRENT_TIMESTAMP AS checked_at
FROM kafka_consumer_lag
WHERE consumer_group = 'job_postings_ingestion'
ORDER BY lag_messages DESC;

-- Check partition health (requires broker metrics)
SELECT
  topic,
  partition_id,
  leader_broker_id,
  replica_count,
  in_sync_replica_count,
  CASE 
    WHEN in_sync_replica_count < replica_count THEN 'UNDER_REPLICATED'
    WHEN leader_broker_id = -1 THEN 'NO_LEADER'
    ELSE 'HEALTHY'
  END AS health_status
FROM kafka_partition_metadata
WHERE topic = 'job-postings'
ORDER BY health_status DESC, partition_id;
```

## Notes

- **Lag ≠ staleness**: A consumer can have zero lag but still process stale records if upstream logic has bugs. Lag is a health signal, not a correctness signal.
- **Per-partition monitoring is critical**: Aggregate lag masks skew; one hot partition with 500k lag messages and nine healthy partitions will average as "fine" but your data is wrong.
- **Consumer lag offset storage matters**: Offset commits to ZooKeeper are slow; Kafka brokers (default in modern versions) are fast but require careful group coordination to avoid duplicate processing on rebalance.
- **Connects to backpressure and scaling**: High lag is often a signal to scale consumers horizontally, but only if lag is growing across all partitions; if one partition lags, you may have a hot key problem instead.
- **Revisit retention policy**: Lag monitoring is moot if your Kafka retention is 7 days but lag exceeds that; offsets will be lost and consumers will fail; retention and lag SLA must be aligned.
