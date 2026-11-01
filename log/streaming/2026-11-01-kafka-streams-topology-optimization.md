---
date: 2026-11-01
phase: streaming
topic: Kafka Streams topology optimization
---

# Kafka Streams topology optimization

*Streaming and distributed processing*

## Concept

A Kafka Streams topology is the logical DAG (directed acyclic graph) of processors, sources, and sinks that defines how data flows and transforms. Optimization focuses on reducing latency, memory footprint, and unnecessary repartitioning—critical because streams are unbounded and processing happens continuously. Without thoughtful topology design, you accumulate state you don't need, trigger expensive shuffle operations on every record, or create bottlenecks where one slow processor blocks all downstream consumers.

The most common culprit is *repartitioning overhead*. Every time you perform a stateful operation (join, aggregate, window) on a key that doesn't match the input topic's partitioning, Kafka Streams must repartition the stream—sending all records through a changelog topic and a shuffle. Doing this multiple times in a single topology can double or triple latency. Similarly, keeping large state stores for long windows or high-cardinality keys bloats memory and slows recovery on rebalance.

Optimization means: choose join strategies that minimize repartitioning, suppress changelog emissions for intermediate results, prune state aggressively with grace periods and retention windows, and validate the topology graph with `describe()` to spot unnecessary branches before deployment.

## Practice

**Problem:** You need to enrich job postings with a running count of posts per location and filter for remote roles posted in the last 7 days. A naive approach applies a stateful aggregate then a filter, causing two separate state stores and potential repartitioning if the key changes mid-pipeline.

```sql
-- Optimized topology: aggregate *after* filtering and keying to location
SELECT 
    job_location,
    job_posted_date,
    COUNT(*) OVER (
        PARTITION BY job_location 
        ORDER BY job_posted_date 
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS posting_count_per_location
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_posted_date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY job_location, job_posted_date;
```

In Kafka Streams code: filter first, then branch by `job_location` (repartition once), then apply `aggregate()`. This reduces state store count and ensures repartitioning happens only once on the filtered, smaller dataset.

## Notes

- **Changelog suppression**: Use `.suppress(Suppressed.untilWindowCloses())` to avoid emitting intermediate changelog records for aggregates within tumbling windows; only emit the final result per window.
- **State store sizing**: Always set explicit retention windows and grace periods (`grace(Duration.ofMinutes(5))`) to prevent unbounded state growth; expired records are automatically purged.
- **Topology testing**: Call `Topology.describe()` in unit tests to validate the DAG structure; catch unnecessary repartitions and multi-hop joins before production.
- **Co-partitioning**: Ensure both sides of a join are keyed identically and on the same topic partition count; mismatches force silent repartitioning that's hard to debug.
- **Adjacent topics**: Connect to exactly-once semantics (idempotence + transactions), state store changelog compaction (log cleanup policy), and interactive queries for real-time state inspection from external services.
