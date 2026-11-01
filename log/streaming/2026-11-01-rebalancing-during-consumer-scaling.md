---
date: 2026-11-01
phase: streaming
topic: Rebalancing during consumer scaling
---

# Rebalancing during consumer scaling

*Streaming and distributed processing*

## Concept

Rebalancing is the automatic redistribution of topic partitions across consumer instances when the group membership changes—a consumer joins, leaves, or fails. Without rebalancing, new consumers sit idle while existing ones remain overloaded, or data from failed consumers is never processed. During rebalancing, the group enters a "stop-the-world" pause where no consumer reads or commits offsets; all processing halts until the broker assigns partitions and consumers resume from their last committed positions.

The timing and strategy of rebalancing directly impacts throughput and latency. A poor rebalancing strategy (e.g., sticky assignment that doesn't balance load fairly) can cause uneven partition distribution, leaving some consumers with 10× more data than others. Conversely, overly aggressive rebalancing—triggered by slow consumers timing out—creates cascading failures: timeouts trigger rejoins, which trigger rebalancing, which delays processing, which causes more timeouts.

In a streaming job that enriches job postings by salary range and work-from-home eligibility, scaling from 2 to 5 consumers must quickly hand off partitions so new consumers start pulling unprocessed records. If rebalancing stalls or assigns partitions poorly, recent job postings queue up in the broker while the system waits, defeating the real-time goal.

## Practice

**Problem:** You have a Kafka topic `job_postings_events` with 12 partitions, consumed by a group that initially has 3 instances. After 30 minutes, you scale to 6 instances. How do you ensure even load distribution and minimal reprocessing during rebalancing?

```sql
-- Simulate tracking which partitions are assigned and their lag
-- In practice, monitor via consumer metrics APIs or Kafka Connect

-- 1. Verify partition count is ≥ number of consumers (ideal ratio: partitions/consumers)
-- Here: 12 partitions / 6 consumers = 2 partitions per consumer

-- 2. Use range or round-robin assignment (avoid sticky if load is imbalanced)
-- In consumer config:
-- partition.assignment.strategy=org.apache.kafka.clients.consumer.RoundRobinAssignor

-- 3. Before scaling, tune session timeout to avoid false-positive timeouts:
-- session.timeout.ms=30000 (default: allows 30s before broker marks consumer dead)
-- heartbeat.interval.ms=10000 (send heartbeat every 10s)

-- 4. Track offset commits to avoid reprocessing:
-- On job_postings_fact, store the committed offset and event_timestamp:
SELECT 
  partition_id,
  consumer_instance_id,
  MAX(committed_offset) AS last_committed_offset,
  MAX(job_posted_date) AS last_processed_date,
  COUNT(*) AS records_since_last_rebalance
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 1 HOUR
GROUP BY partition_id, consumer_instance_id
ORDER BY partition_id;

-- 5. Monitor rebalancing time in logs (millis between "revoke" and "assign" callbacks)
-- Rebalancing should complete in < 60 seconds for healthy deployments
```

## Notes

- **Heartbeat misconfiguration is the #1 cause of unwanted rebalancing:** if `heartbeat.interval.ms` is too large or GC pauses exceed `session.timeout.ms`, the broker assumes the consumer died and triggers rebalancing. Set heartbeat to ⅓ of session timeout.
- **Sticky assignment reduces partition movement** (minimizing reprocessing and local state loss), but can create uneven load if old consumers consume much faster than new ones—profile before enabling.
- **Rebalancing connects to state stores and windowing:** if you maintain local join state or tumbling windows, rebalancing clears in-flight state; design for idempotence and use changelog topics to restore state on new assignments.
- **Consumer lag grows during rebalancing:** monitor lag metrics before, during, and after scaling events; expect a spike, then recovery as new consumers catch up.
- **Revisit offset commit strategy:** auto-commit is risky during high rebalance frequency; explicit commits at processing boundaries (e.g., after enriching and storing job_postings_fact) ensure exactly-once semantics.
