---
date: 2026-09-27
phase: streaming
topic: Static membership and sticky assignment patterns
---

# Static membership and sticky assignment patterns

*Streaming and distributed processing*

## Concept

Static membership and sticky assignment ensure that consumer instances in a distributed system maintain consistent partition ownership across rebalances, rather than shuffling assignments whenever group membership changes. In Kafka consumer groups, without sticky assignment, a rebalance can cause every partition to be reassigned to different consumers, forcing unnecessary state rebuilds and cache invalidates. Sticky assignment minimizes the shuffle—only newly added or removed consumers cause reassignments, while existing consumers keep their original partitions. This matters acutely in streaming jobs where consumers maintain local state (joins, aggregations, windowed computations) or where partition ordering guarantees depend on consistent assignment.

Static membership takes this further by allowing consumers to rejoin a group with a *fixed instance ID* rather than a transient client ID, preventing rebalances during temporary network hiccups or rolling deployments. Without it, a brief disconnection triggers a full rebalance even when the consumer returns within seconds. With static membership configured (`group.instance.id`), the broker holds the assignment for a grace period, and the returning consumer reclaims its partitions without disrupting the group.

The practical impact: without sticky or static assignment, a 30-second deployment of 10 consumers can trigger 10+ rebalances, each pausing all processing for seconds to minutes, duplicating state initialization, and potentially violating ordering semantics for keyed topics.

## Practice

**Problem:** You're streaming job postings into an event log partitioned by `job_location`. Each consumer builds an in-memory index of recent postings per location to enrich downstream queries. During a rolling deployment, consumers drop and rejoin. Without sticky assignment, all location indexes are rebuilt on every rebalance, causing 5-minute gaps where the index is stale or missing.

```sql
-- Consumer group configuration (pseudo-code for Kafka properties)
-- Enable sticky assignment (default in Kafka 2.4+, but verify)
partition.assignment.strategy=org.apache.kafka.clients.consumer.StickyAssignor

-- Enable static membership (requires Kafka 2.3+)
group.instance.id=job-enricher-instance-${HOSTNAME}
session.timeout.ms=10000
heartbeat.interval.ms=3000

-- In your streaming job (Spark Structured Streaming / Kafka consumer):
-- Before: Every rebalance rebuilds the index
SELECT job_location, 
       COLLECT_LIST(job_id) as recent_job_ids,
       MAX(job_posted_date) as latest_post_date
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 7 DAY
GROUP BY job_location
-- With sticky + static membership: same logic, but assignment stays stable
-- across rebalances → index persists → no stale windows
```

## Notes

- **Mistake:** Confusing sticky assignment (broker-side minimization) with static membership (client-side persistence via instance ID). You need both for full protection: sticky handles planned rebalances, static handles transient disconnects.

- **Mistake:** Setting `session.timeout.ms` too short; if a consumer pauses (GC, network jitter) longer than timeout, it's evicted despite static membership. Balance responsiveness against false-positive eviction—3–10 seconds typical for stateful jobs.

- **Connection:** Sticky/static assignment directly enables **exactly-once semantics** in streaming by reducing spurious rebalances that can duplicate or lose records during state transitions.

- **Connection:** This pattern is foundational for **local state stores** in stream processors (e.g., Kafka Streams, Flink) that rely on keyed partitions landing on the same instance. Rebalances invalidate the guarantee.

- **Revisit:** Monitor rebalance frequency and duration in production (via consumer lag metrics, broker logs). A production job should rebalance only on intentional scaling or failure, not per-deployment.
