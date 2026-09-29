---
date: 2026-09-29
phase: streaming
topic: Interactive queries in Kafka Streams
---

# Interactive queries in Kafka Streams

*Streaming and distributed processing*

## Concept

Interactive queries in Kafka Streams allow you to query the *current state* of a stream processing application without stopping it. They expose state stores (KTables, WindowStores, SessionStores) via `StateStore` APIs, letting you ask "what is the value for key X *right now*?" while the stream continues running. This is critical because stream processors maintain materialized views of aggregations, joins, and lookups—and those views are useless if you can't access them until the job finishes (which, in a streaming context, may never happen).

Without interactive queries, you're forced to either write results to an external database (adding latency and I/O overhead) or wait for batch aggregations. This breaks real-time dashboards, feature stores, and serving layers that need low-latency lookups. For example, if you're aggregating job postings by location, you cannot answer "how many remote jobs posted today?" without querying the running state store directly—not the changelog topic, not a sink database.

The tradeoff is consistency: state stores offer eventual consistency across topology replicas and may lag slightly behind the input stream. You must be aware of whether you're hitting a standby replica (stale) versus the active replica (fresher).

## Practice

**Problem:** You run a KStream aggregation counting job postings by `job_location`, updated every 10 seconds. A dashboard needs to display live counts for each location. How do you expose this data without sinking to a database?

```sql
-- Kafka Streams topology (pseudo-code):
KStream<String, JobPosting> postings = builder.stream("job_postings");
KTable<String, Long> counts = postings
  .groupBy((k, v) -> v.job_location)
  .count(Materialized.as("job-counts-store"));

-- Interactive query at serving layer:
ReadOnlyKeyValueStore<String, Long> store = 
  streams.store("job-counts-store", QueryableStoreTypes.keyValueStore());

Long remoteCount = store.get("Remote");
Long sfCount = store.get("San Francisco");

-- Returns immediate snapshot; no database needed, ~5–50ms latency
```

## Notes

- **Common mistake:** Querying a standby replica and assuming you have the latest count; always route queries to the active replica via `streams.allMetadata()` and partition assignment.
- **State store lag:** Interactive queries reflect state *as of the last committed offset*, not microsecond-current; acceptable for dashboards, not for financial reconciliation.
- **Scaling gotcha:** State stores are local to each instance; querying job-location=X on instance-2 when the key lives on instance-1 returns null. Use a routing layer or RPC across topology nodes.
- **Adjacent: Interactive Queries & Changelog Topics** – understand that the state store is *derived* from the changelog topic; losing state requires replay from the changelog, so always enable changelog topics and replication.
- **Revisit:** Combine with `GlobalKTable` for broadcast-style joins where every instance needs the full reference table in-memory.
