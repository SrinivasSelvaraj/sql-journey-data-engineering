---
date: 2026-10-17
phase: streaming
topic: Kafka consumer groups: parallel processing and rebalancing
---

# Kafka consumer groups: parallel processing and rebalancing

*Streaming and distributed processing*

## Concept

A **consumer group** is a set of Kafka consumers that collectively read from one or more topics, with each partition assigned to exactly one consumer at a time. This design enables horizontal scaling: instead of a single consumer becoming a bottleneck, you can add more consumers to the group and automatically distribute the load across partitions. When a consumer joins or leaves the group, Kafka triggers a **rebalance**—a brief pause where partition assignments are recalculated and offset management is coordinated. Rebalancing matters because it's the mechanism that keeps a distributed system resilient; without it, adding capacity would require manual intervention or message loss.

What breaks without consumer groups: (1) you lose automatic failover—if your only consumer dies, messages pile up unread; (2) you cannot parallelize—a single consumer cannot consume faster than its network and CPU allow; (3) you have no coordination—multiple independent consumers reading the same partition will miss or duplicate messages. In production, rebalancing also costs latency; during a rebalance, the group briefly stops consuming, so poorly tuned rebalance parameters can create noticeable gaps in streaming pipelines.

## Practice

**Problem:** You have a Kafka topic `job_postings` with 6 partitions receiving job posting events. You want to enrich each posting with salary percentile calculations (comparing `salary_year_avg` within `job_location`). You've provisioned three consumer instances, but rebalancing happens frequently and causes 10–15 second gaps in processing. You need to tune the consumer group to reduce rebalance frequency while maintaining fault tolerance.

```sql
-- Consumer group configuration (in code, not SQL, but shown here for reference)
-- Apply these settings when creating your Kafka consumer:

properties = {
  'bootstrap.servers': 'kafka-broker:9092',
  'group.id': 'job_postings_enrichment_group',
  'auto.offset.reset': 'earliest',
  
  -- Rebalance tuning:
  'session.timeout.ms': 30000,           -- Consumer must heartbeat within 30s or is considered dead
  'heartbeat.interval.ms': 10000,        -- Send heartbeat every 10s (1/3 of session timeout)
  'max.poll.interval.ms': 300000,        -- Allow 5 minutes between poll() calls for processing
  
  -- Partition assignment:
  'partition.assignment.strategy': 'org.apache.kafka.clients.consumer.RoundRobinAssignor',
  
  -- Offset management:
  'enable.auto.commit': False,            -- Manually commit after enrichment
  'isolation.level': 'read_committed'
}

-- Application logic (pseudocode mapped to Kafka semantics):
-- For each message in job_postings topic:
SELECT 
  jp.job_id,
  jp.job_title_short,
  jp.salary_year_avg,
  PERCENT_RANK() OVER (PARTITION BY jp.job_location ORDER BY jp.salary_year_avg) 
    AS salary_percentile,
  jp.job_work_from_home,
  jp.job_posted_date,
  jp.job_location
FROM job_postings_fact jp
-- Enrich in-stream, then commit offset after writing to enriched topic
```

## Notes

- **Session timeout vs. max poll interval:** Session timeout catches dead brokers quickly; max poll interval should be long enough to handle your enrichment logic. Set heartbeat interval to 1/3 of session timeout. Too aggressive = thrashing rebalances; too loose = slow failure detection.

- **Rebalance strategy matters:** RoundRobin distributes evenly across consumers; Range assigns consecutive partitions (better for ordering guarantees but imbalanced if partitions differ); Sticky tries to keep assignments stable across rebalances (minimizes data re-processing). Choose based on your ordering and state requirements.

- **Manual offset commits vs. auto-commit:** Auto-commit is simpler but risks losing messages if a consumer crashes mid-enrichment. Manual commits (after writing enriched data) give you exactly-once semantics but require careful error handling.

- **Rebalance listener:** Register a `ConsumerRebalanceListener` to flush in-flight state, close file handles, or warm up caches when partitions are reassigned. Missing this is a common source of data loss or resource leaks.

- **Consumer lag monitoring:** Track lag (latest offset − committed offset) per partition. High lag after rebalances signals misconfigured timeouts or processing bottlenecks; use this signal to right-size your consumer count or tune partition count.
