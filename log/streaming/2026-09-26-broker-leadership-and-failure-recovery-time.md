---
date: 2026-09-26
phase: streaming
topic: Broker leadership and failure recovery time
---

# Broker leadership and failure recovery time

*Streaming and distributed processing*

## Concept

In a streaming Kafka cluster, broker leadership determines which broker handles read/write coordination for a partition. When a broker fails, the cluster must elect a new leader—this failover window is the **failure recovery time**. During recovery, clients experience latency spikes, potential message loss (if replication factor is insufficient), and out-of-order consumption if consumers reconnect mid-election.

Broker leadership matters most when you have strict SLAs on data arrival and processing. E-commerce platforms, real-time analytics pipelines, and financial feeds cannot tolerate leadership elections taking 30+ seconds. Without fast recovery, downstream aggregations (like rolling averages of job postings per location) fall out of sync, late-arriving events pile up, and consumers tracking state become inconsistent.

The cost of slow failure recovery compounds in chains: if a leader takes 45 seconds to failover and your pipeline processes 1 million events/sec, you lose 45M events from the recovery window alone. Add consumer lag rebuilding, and your SLA window evaporates.

## Practice

**Problem:** You're aggregating job postings by location in real-time. A Kafka broker fails mid-stream. Your consumer group needs to resume processing without skipping or duplicating records from the `job_postings_fact` table. Design a recovery checkpoint that captures both the offset and the last-processed job_id.

```sql
-- Create an idempotent state table to track consumption progress
CREATE TABLE job_posting_consumer_state (
  consumer_group_id VARCHAR(255),
  partition_id INT,
  last_processed_offset BIGINT,
  last_processed_job_id INT,
  checkpoint_timestamp TIMESTAMP,
  PRIMARY KEY (consumer_group_id, partition_id)
);

-- After processing each micro-batch, commit state atomically
INSERT INTO job_posting_consumer_state 
  (consumer_group_id, partition_id, last_processed_offset, last_processed_job_id, checkpoint_timestamp)
VALUES ('job_analytics_group', 0, 15847, 98765, NOW())
ON CONFLICT (consumer_group_id, partition_id) 
DO UPDATE SET 
  last_processed_offset = EXCLUDED.last_processed_offset,
  last_processed_job_id = EXCLUDED.last_processed_job_id,
  checkpoint_timestamp = EXCLUDED.checkpoint_timestamp;

-- On recovery, resume from the last safe offset
SELECT last_processed_offset, last_processed_job_id 
FROM job_posting_consumer_state 
WHERE consumer_group_id = 'job_analytics_group' AND partition_id = 0;
```

## Notes

- **Confusing "failure recovery time" with "rebalance time":** Leadership failover (broker down) is different from consumer group rebalancing (consumer down). Broker failover is usually faster (< 10s with proper config) but more disruptive; rebalancing can cascade across the group.
- **Replication factor and min.insync.replicas trade-off:** Higher replication slows writes but protects against broker loss. Set `min.insync.replicas=2` to guarantee durability, but accept slower failover as more replicas must catch up.
- **Adjacent: exactly-once semantics and idempotent writes.** Broker failover can cause duplicate message delivery if you don't checkpoint *after* processing; combine offset commits with idempotent upserts (like the `ON CONFLICT` above) to guarantee no duplicates.
- **Monitor with broker-level metrics:** Track `UnderReplicatedPartitions`, `OfflinePartitionsCount`, and controller election latency. Slow elections signal config issues (GC pauses, slow disk I/O) before they hit your data pipeline.
- **Revisit: consumer lag, retention policy, and log compaction.** Slow brokers create lag; lag + short retention means consumers can't catch up after failover.
