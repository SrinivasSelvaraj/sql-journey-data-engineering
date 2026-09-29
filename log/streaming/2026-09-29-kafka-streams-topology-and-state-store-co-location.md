---
date: 2026-09-29
phase: streaming
topic: Kafka Streams topology and state store co-location
---

# Kafka Streams topology and state store co-location

*Streaming and distributed processing*

## Concept

Kafka Streams topology and state store co-location means placing the state store (changelog topic and local store) on the same machine as the task processing that state. Without co-location, every stateful operation (aggregation, join, session window) forces the stream processor to serialize state, send it over the network, wait for a remote response, then deserialize—destroying throughput and adding latency spikes during rebalances.

Co-location matters most when you have high-volume stateful workloads: windowed aggregations over millions of events, stream-stream joins, or deduplication. A single misaligned rebalance can scatter state stores across the cluster, causing each task to rebuild its local store from the changelog topic, effectively pausing processing.

Without proper co-location, you lose fault tolerance guarantees too. If a task moves to a different broker before its state store changelog is fully replicated there, you risk data loss during a crash. Kafka Streams handles this automatically when you configure `num.standby.replicas` and let the framework respect rack-awareness and broker assignment.

## Practice

**Problem:** You need to aggregate job postings by `job_location` every hour, calculating total count and average salary. The input stream is high-volume (50k events/sec), and you want to avoid network round-trips during aggregation.

```sql
-- Kafka Streams topology (pseudo-code logic)
stream
  .groupByKey(Serdes.String(), postingSerdes)  -- group by job_location
  .windowedBy(TimeWindows.of(Duration.ofHours(1)))
  .aggregate(
    () -> new LocationStats(0, 0.0),           -- initializer (count, sum_salary)
    (location, posting, stats) -> new LocationStats(
      stats.count + 1,
      stats.sumSalary + posting.salary_year_avg
    ),
    Serdes.String(),
    locationStatsSerdes
  )
  .toStream()
  .to("job_location_hourly_stats", Produced.with(windowedSerdes, locationStatsSerdes));

-- State store (internal) resides locally with the task processing each job_location partition
-- Changelog topic: job_location_hourly_stats-aggregate-changelog
-- Parallelism = num partitions in input topic = co-located tasks
```

Key: set `num.standby.replicas=1` and `rack.aware.assignment.tags` to ensure changelog replicas sit on different racks, so state rebuilds stay local-ish during failover.

## Notes

- **Rebalancing is the killer.** During a rebalance, if the state store changelog topic has fewer replicas than standby replicas configured, Kafka Streams must restore from scratch—avoid this by matching `num.standby.replicas` to your replication factor.
- **Changelog topics are internal contracts.** Never delete or manually edit a changelog topic; it's the source of truth for state reconstruction. Name them explicitly in code to track them in your cluster.
- **Rack-awareness prevents correlated failures.** Use `broker.rack` and `replica.selector.class` to spread changelog replicas across racks so a single rack outage doesn't force full state rebuild.
- **Interactive queries require co-location too.** If you query state from a different broker than the one holding that state partition, you're going remote; use `StateStore.queryableStoreName()` carefully.
- **Adjacent topics:** processor topology layout, exactly-once semantics (requires changelog), interactive queries (QueryableStateStore), and changelog compaction policies (tune `log.cleanup.policy` for state stores, often `compact` + `delete` for hybrid retention).
