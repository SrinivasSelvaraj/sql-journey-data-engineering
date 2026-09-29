---
date: 2026-09-29
phase: streaming
topic: Exactly-once processing in Kafka Streams
---

# Exactly-once processing in Kafka Streams

*Streaming and distributed processing*

## Concept

Exactly-once processing guarantees that each input record contributes to the output state exactly one time, even when failures occur. In Kafka Streams, this is achieved through idempotent writes combined with transactional processing: the consumer offset and the state store update are committed atomically, so a crash and replay never double-count or lose records. Without it, a broker failure mid-aggregation could cause duplicate records to be processed, inflating counts or corrupting financial totals—a critical issue in systems handling payments, inventory, or metrics.

The guarantee works because Kafka Streams coordinates three things: (1) reading from a specific offset, (2) updating local state stores, and (3) writing downstream to Kafka topics, all within a single transaction. If the process crashes before commit, the offset reverts and processing replays from the last safe point. The default mode is `at-least-once`; enabling `processing.guarantee=exactly_once_v2` (or the older `exactly_once`) triggers this behavior, though it trades throughput for correctness.

Note that exactly-once applies *within* Kafka Streams; if you sink data to an external system (database, API), you must ensure the sink itself is idempotent or transactional, otherwise a replay can still create duplicates downstream.

## Practice

**Problem:** A data pipeline ingests job posting records into Kafka. You aggregate salary data by job title to compute running averages. Without exactly-once guarantees, a consumer restart could re-process old messages, inflating the salary total and skewing the average. Write a Kafka Streams topology that ensures each posting contributes to the average exactly once.

```sql
-- Conceptual schema (the state store logic below handles aggregation)
-- Input topic: job_postings
--   {job_id, job_title_short, salary_year_avg, job_posted_date}
-- Output topic: salary_averages_by_title
--   {job_title_short, avg_salary, record_count, window_start, window_end}

-- Kafka Streams DSL (pseudo-code, Java/Scala syntax):
StreamsBuilder builder = new StreamsBuilder();

builder
  .stream("job_postings", Consumed.with(Serdes.String(), jobPostingSerde))
  .groupByKey((jobId, posting) -> posting.job_title_short)
  .windowedBy(TimeWindows.ofSizeWithNoGrace(Duration.ofHours(1)))
  .aggregate(
    () -> new SalaryAggregate(0.0, 0L),  // initializer
    (key, posting, agg) -> {             // adder
      agg.total_salary += posting.salary_year_avg;
      agg.count += 1;
      return agg;
    },
    Materialized.as("salary-store")      // state store name
  )
  .toStream()
  .mapValues(agg -> new SalaryAverage(
    agg.total_salary / agg.count,
    agg.count
  ))
  .to("salary_averages_by_title", Produced.with(Serdes.String(), averageSerde));

// Enable exactly-once in properties:
properties.put(StreamsConfig.PROCESSING_GUARANTEE_CONFIG, 
  StreamsConfig.EXACTLY_ONCE_V2);
```

The state store is backed by a changelog topic; on restart, Kafka Streams replays only committed offsets, so the aggregate is rebuilt deterministically without duplication.

## Notes

- **Transactional writes matter downstream:** exactly-once in Kafka Streams does not automatically make your sink idempotent. If you write to PostgreSQL or S3, use upserts (INSERT … ON CONFLICT) or versioned keys to avoid duplicates on replay.
- **`exactly_once_v2` vs. legacy:** version 2 is faster and doesn't require a separate changelog topic for every processor; prefer it in Kafka ≥2.5. The old `exactly_once` used double-buffering and is slower.
- **State store recovery overhead:** enabling exactly-once increases latency on recovery because Kafka Streams must replay the changelog to rebuild local stores. Monitor recovery time in production.
- **Windowing and time semantics:** exactly-once guarantees work across event-time, processing-time, and session windows, but the clock matters. Grace periods and retention policies can interact with commit boundaries in non-obvious ways—test edge cases around window closure.
- **Related:** idempotency at the source (deduplication by ID), transactional outbox pattern, and distributed snapshot consistency (Chandy–Lamport). Revisit if deploying sinks to non-Kafka systems.
