---
date: 2026-10-17
phase: streaming
topic: Stream topology: sources, operators, sinks design
---

# Stream topology: sources, operators, sinks design

*Streaming and distributed processing*

## Concept

A stream topology defines the shape and flow of a streaming pipeline: where data enters (sources), how it's transformed (operators), and where it lands (sinks). Unlike batch jobs that process bounded datasets, streaming topologies must handle unbounded, out-of-order arrivals while maintaining correctness and state consistency. Without clear topology design, streams become fragile—late-arriving job postings overwrite salary data, duplicate events cause billing errors, and operator failures cascade without recovery boundaries.

Sources ingest from message brokers (Kafka, Kinesis), databases, or APIs. Operators filter, enrich, aggregate, or join streams—often maintaining stateful windows (tumbling, sliding, session) to bucket continuous data into analyzable chunks. Sinks persist results to data warehouses, caches, or downstream systems. The critical difference from batch: operators must be deterministic and idempotent because events may arrive out of order or be replayed on failure.

Topology design forces you to answer: How wide is my window? Do I need exactly-once semantics? Can I afford to drop late data or must I backfill? Where do I checkpoint state? These decisions ripple through latency, cost, and data quality.

## Practice

**Problem:** A real-time dashboard needs to show the rolling 24-hour average salary by job title. Job postings arrive out of order with delays up to 2 hours. You must handle retractions (job posted_date corrections) and only emit results when the window is 3 hours old to allow late data.

```sql
-- Topology: Source → Tumbling Window Operator → Filter Operator → Sink
-- Pseudocode in Flink/Beam SQL style

CREATE TEMPORARY VIEW job_stream AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_posted_date,
    CURRENT_TIMESTAMP AS event_time
  FROM kafka_topic 'job-postings'
  WHERE salary_year_avg IS NOT NULL
);

-- Operator 1: Tumble by job_posted_date, compute 24h rolling avg
CREATE TEMPORARY VIEW salary_by_title_windowed AS (
  SELECT
    TUMBLE_START(job_posted_date, INTERVAL '1' DAY) AS window_start,
    TUMBLE_END(job_posted_date, INTERVAL '1' DAY) AS window_end,
    job_title_short,
    AVG(salary_year_avg) AS avg_salary_24h,
    COUNT(*) AS job_count,
    MAX(CURRENT_TIMESTAMP) AS max_event_time
  FROM job_stream
  GROUP BY TUMBLE(job_posted_date, INTERVAL '1' DAY'), job_title_short
);

-- Operator 2: Filter—only emit windows closed 3+ hours ago (allow late arrivals)
INSERT INTO postgres_sink (title, avg_salary, window_date, refresh_ts)
SELECT
  job_title_short,
  ROUND(avg_salary_24h, 2),
  window_start,
  CURRENT_TIMESTAMP
FROM salary_by_title_windowed
WHERE CURRENT_TIMESTAMP >= window_end + INTERVAL '3' HOUR;
```

## Notes

- **State management is hidden complexity:** Windows hold in-memory state. Size windows carefully—10M events per title per day = memory explosion. Use RocksDB backing stores for large state.
- **Watermarks, not clocks:** Don't trust `CURRENT_TIMESTAMP`. Use event-time watermarks to know when a window is truly complete; late arrivals should trigger allowed lateness windows, not immediate emission.
- **Idempotency at the sink:** Even with exactly-once guarantees upstream, retry logic means sinks see duplicates. Use job_id as a deduplication key or make updates idempotent (MERGE, not INSERT).
- **Topology testing is painful:** Unit test operators in isolation (mock sources, capture results). Integration test with Testcontainers (Kafka + pipeline runtime) to catch out-of-order and late-arrival bugs.
- **Connected to:** backpressure handling (slow sinks stall sources), checkpoint/savepoint strategy (recovery point granularity), and exactly-once vs. at-least-once tradeoffs (complexity vs. duplicates).
