---
date: 2026-09-06
phase: streaming
topic: Kafka: partitions, replication and consumer group coordination
---

# Kafka: partitions, replication and consumer group coordination

*Streaming and distributed processing*

## Concept

Kafka partitions are the unit of parallelism and durability: each partition is an ordered, immutable log of messages assigned to one broker at a time, but replicated across multiple brokers for fault tolerance. When a producer sends a message, it lands in exactly one partition (determined by key, round-robin, or custom logic); consumers read from partitions in order, but multiple partitions can be read in parallel. Without partitions, you cannot scale beyond a single broker's throughput, and you lose the ability to parallelize consumption across consumer instances.

Replication ensures that if a broker fails, at least one other broker holds a copy of each partition. The leader handles all reads and writes; replicas are passive backups. When the leader dies, the cluster elects a new leader from the in-sync replicas (ISR). Without replication, any broker failure means data loss and service interruption—unacceptable for streaming pipelines that must be always-on.

Consumer groups coordinate which consumer instances read which partitions. Each partition is assigned to exactly one consumer in a group; if you have 5 partitions and 3 consumers, two consumers get 2 partitions each and one gets 1. The group coordinator (a broker) manages this assignment and rebalances when consumers join or leave. Without coordination, consumers would either duplicate reads or miss messages entirely, and offset tracking would become incoherent.

## Practice

**Problem:** You have a Kafka topic `job_postings_stream` with 6 partitions, partitioned by `job_location`. Three consumer instances subscribe to this topic as part of the group `salary_analytics`. Each instance must track the highest average salary seen so far per location and persist it to a table. One instance crashes and is replaced 5 minutes later. How do you ensure no data is lost or double-counted, and how do you query the current state?

```sql
-- 1. Create the state table (consumer-side or post-aggregation)
CREATE TABLE salary_high_water (
  job_location VARCHAR,
  max_salary_year_avg INT,
  last_updated TIMESTAMP,
  PRIMARY KEY (job_location)
);

-- 2. Consumer group reads from job_postings_stream with auto-commit disabled
-- (pseudocode for consumer logic)
-- for record in consumer.poll():
--   max_salary = max(record.salary_year_avg, 
--                    SELECT max_salary_year_avg FROM salary_high_water 
--                    WHERE job_location = record.job_location)
--   UPSERT INTO salary_high_water VALUES (record.job_location, max_salary, NOW())
--   consumer.commit_sync()  -- commit only after successful write

-- 3. Query current state; rebalancing does not affect this table
SELECT 
  job_location,
  max_salary_year_avg,
  last_updated
FROM salary_high_water
ORDER BY max_salary_year_avg DESC;
```

The key: the consumer group automatically rebalances when the instance rejoins; the new instance resumes from the last committed offset for its assigned partitions, skipping already-processed messages.

## Notes

- **Offset management is critical:** auto-commit can lose data (commit before processing finishes); manual synchronous commits are safer but slower. Use Kafka's consumer offset topic (`__consumer_offsets`) to inspect group state.
- **Rebalancing causes a pause:** when a consumer joins or leaves, all instances in the group briefly stop consuming while the coordinator reassigns partitions. Design for this pause (e.g., with stateful stores or external databases).
- **Partition key strategy matters:** if you key by `job_location` but 80% of postings are from one location, that partition becomes a bottleneck and replication lag increases. Use uniform key distribution or accept that some partitions will be hotter.
- **ISR and min.insync.replicas:** if you require acks=all but min.insync.replicas is 1, you have false durability. Set min.insync.replicas ≥ 2 and use acks=all for exactly-once semantics in critical pipelines.
- **Consumer lag monitoring:** use tools like Burrow or Kafka's built-in metrics to track how far behind each consumer group is; growing lag signals slow processing or rebalance thrashing and points to capacity or logic issues early.
