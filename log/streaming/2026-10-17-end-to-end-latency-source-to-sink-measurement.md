---
date: 2026-10-17
phase: streaming
topic: End-to-end latency: source to sink measurement
---

# End-to-end latency: source to sink measurement

*Streaming and distributed processing*

## Concept

End-to-end latency measures the time elapsed from when a data event is generated at the source until it is queryable or actionable at the sink. In streaming systems, this is critical because data arrives continuously and out of order—a job posting may be ingested 5 seconds after posting, transformed 3 seconds later, and written to the data warehouse 2 seconds after that. Without measuring this, you cannot distinguish between slow ingestion, slow processing, or slow storage, making it impossible to meet SLAs or debug bottlenecks.

The stakes are high in time-sensitive applications: a recruiter querying "jobs posted in the last hour" will see stale data if end-to-end latency exceeds 60 minutes; a real-time dashboard will mislead users; fraud detection or anomaly systems will miss windows of opportunity. Latency becomes invisible when you conflate processing time (when Kafka receives it) with event time (when the job was actually posted), or when you lack tracing IDs to connect a record from source to sink.

Without explicit measurement, latency compounds: a 100ms source delay + 200ms transformation delay + 150ms sink write might seem acceptable individually, but adds up to 450ms user-facing latency, which is unacceptable for interactive systems. You need instrumentation at every stage and a way to correlate records end-to-end.

## Practice

**Problem:** You are building a real-time job board. Job postings arrive via an API, are deduplicated and enriched in Kafka, then written to a Redshift warehouse. You need to measure how long it takes from API ingestion to when a job appears in the final fact table, and alert if latency exceeds 5 minutes for any job.

```sql
-- Add instrumentation columns to job_postings_fact
ALTER TABLE job_postings_fact ADD COLUMN (
  source_timestamp TIMESTAMP NOT NULL,      -- when API received the event (event time)
  ingestion_timestamp TIMESTAMP NOT NULL,   -- when it entered Kafka
  transformation_timestamp TIMESTAMP NOT NULL, -- when it was transformed
  sink_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- when it landed in Redshift
  trace_id VARCHAR(36) NOT NULL             -- unique identifier to track record end-to-end
);

-- Measure end-to-end latency for each job
SELECT
  job_id,
  trace_id,
  job_posted_date,
  source_timestamp,
  sink_timestamp,
  DATEDIFF(millisecond, source_timestamp, sink_timestamp) AS e2e_latency_ms,
  DATEDIFF(millisecond, source_timestamp, ingestion_timestamp) AS source_to_kafka_ms,
  DATEDIFF(millisecond, ingestion_timestamp, transformation_timestamp) AS kafka_to_transform_ms,
  DATEDIFF(millisecond, transformation_timestamp, sink_timestamp) AS transform_to_sink_ms
FROM job_postings_fact
WHERE sink_timestamp >= CURRENT_TIMESTAMP - INTERVAL '1 hour'
  AND DATEDIFF(millisecond, source_timestamp, sink_timestamp) > 5 * 60 * 1000 -- > 5 minutes
ORDER BY e2e_latency_ms DESC;
```

This query isolates which stage is the bottleneck and alerts to SLA violations.

## Notes

- **Confusing event time with processing time:** A Kafka offset timestamp does not reflect when the event occurred; always carry the source-generated timestamp through the pipeline or you lose visibility into true latency.
- **Missing trace IDs:** Without a unique identifier flowing through every stage (from API → Kafka → transform → warehouse), you cannot correlate which record caused a latency spike; use UUIDs or hash the key + source timestamp.
- **Watermarks and late-arriving data:** In streaming, you must decide how long to wait for late data before closing a window; this is a trade-off between completeness and latency that requires monitoring percentile latency (p50, p95, p99) rather than just averages.
- **Sink write batching vs. real-time queryability:** Writing to the warehouse in micro-batches reduces network overhead but increases latency; measure latency to the commit point, not just to disk, and account for time before a query can see the data.
- **Adjacent: distributed tracing, watermarking, backpressure:** Consider tools like OpenTelemetry or Datadog to trace records across services; understand how backpressure (when downstream is slow) propagates upstream and inflates latency; revisit this when you add aggregations or state stores.
