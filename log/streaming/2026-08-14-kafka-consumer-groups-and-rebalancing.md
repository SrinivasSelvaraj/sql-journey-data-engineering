---
date: 2026-08-14
phase: streaming
topic: Kafka: consumer groups and rebalancing
---

# Kafka: consumer groups and rebalancing

*Streaming and distributed processing*

## Concept

A **consumer group** is a set of Kafka consumers that collectively subscribe to the same topics and divide the work of consuming partitions among themselves. Each partition is assigned to exactly one consumer in the group, ensuring no two consumers in the same group read the same message. When consumers join or leave the group, Kafka triggers a **rebalance**: a brief stop-the-world event where partition assignments are recalculated and redistributed. This mechanism enables horizontal scaling—add more consumers to a group to process a topic faster—while guaranteeing that messages are processed exactly once per consumer group.

Rebalancing matters because real-time data pipelines cannot tolerate message loss or duplication across consumer instances. Without consumer groups, you'd need manual partition assignment and no automatic failover. Without rebalancing, a crashed consumer would leave its partitions unassigned indefinitely. The cost of rebalancing is a processing pause (typically seconds) during which no messages are consumed; this trade-off is worth the automatic recovery and load distribution it provides.

What breaks without it: duplicate processing (multiple consumers reading the same partition independently), uneven load distribution (some consumers idle while others are overloaded), and no automatic recovery when a consumer crashes. Streaming aggregations, windowed joins, and stateful processing all depend on stable partition assignment to maintain correctness.

## Practice

**Problem:** You are ingesting a real-time stream of job postings into Kafka (one topic, multiple partitions by job_id). You have three consumer instances that enrich postings with salary trends and write to a data warehouse. One consumer crashes. How do you ensure the partition that was assigned to the crashed consumer is picked up by remaining healthy consumers without manual intervention?

```sql
-- After crash, the consumer group rebalances automatically.
-- Verify group status and member assignments:

-- Check consumer group status (Kafka CLI):
kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --group job-postings-enrichment \
  --describe

-- Output shows:
-- TOPIC            PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG  CONSUMER-ID  HOST
-- job_postings     0          1500            1520            20   consumer-2   /10.0.0.5
-- job_postings     1          2100            2105            5    consumer-3   /10.0.0.6
-- job_postings     2          800             825             25   consumer-1   /10.0.0.4
-- (After crash of consumer-1, rebalance occurs automatically)

-- In application code (Python Kafka consumer):
from kafka import KafkaConsumer
import json

consumer = KafkaConsumer(
    'job_postings',
    group_id='job-postings-enrichment',
    bootstrap_servers=['localhost:9092'],
    on_partitions_revoked=lambda revoked: print(f"Lost: {revoked}"),
    on_partitions_assigned=lambda assigned: print(f"Gained: {assigned}"),
    auto_offset_reset='earliest',
    enable_auto_commit=True,
    max_poll_records=100
)

for message in consumer:
    posting = json.loads(message.value)
    # Enrich and write to warehouse
    print(f"Processing job {posting['job_id']} from partition {message.partition}")
```

## Notes

- **Rebalance storms:** Too-frequent rebalances happen when consumers crash repeatedly or when `session.timeout.ms` is too short. Set it appropriately (default 10s) and monitor consumer lag.
- **Offset commit strategy:** Use `enable_auto_commit=True` for at-least-once semantics, but manual commits offer exactly-once if you commit *after* successful downstream processing.
- **Stop-the-world impact:** During rebalance, no messages flow. For SLAs, use rebalance listeners (`on_partitions_revoked`, `on_partitions_assigned`) to flush state or log metrics.
- **Static vs. dynamic membership:** Static membership (assign consumer IDs explicitly) reduces rebalance time by avoiding full reassignment on temporary disconnects—useful for stateful consumers.
- **Related: offset management and consumer lag**—track `current_offset` vs `log_end_offset` to detect slow consumers before they cause cascading failures.
