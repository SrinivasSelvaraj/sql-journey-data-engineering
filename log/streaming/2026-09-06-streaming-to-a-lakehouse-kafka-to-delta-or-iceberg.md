---
date: 2026-09-06
phase: streaming
topic: Streaming to a lakehouse: Kafka to Delta or Iceberg
---

# Streaming to a lakehouse: Kafka to Delta or Iceberg

*Streaming and distributed processing*

## Concept

Streaming data from Kafka into a lakehouse (Delta Lake or Apache Iceberg) solves the problem of ingesting unbounded, out-of-order events into analytical storage while maintaining ACID guarantees and schema evolution. Unlike batch pipelines that process data in discrete windows, lakehouse streaming ingestion accepts events continuously and makes them queryable within seconds, which is essential for real-time dashboards, fraud detection, or SLA monitoring.

Without this pattern, you either buffer events in a message queue indefinitely (costly and risky), or write to a data warehouse with eventual consistency gaps and no transactional guarantees (leading to duplicates, missing records, or partial overwrites during failures). Delta and Iceberg solve this by combining Kafka's fault tolerance with the ACID semantics and columnar performance of a data lake—you get both speed and correctness.

The key challenge is handling late-arriving and out-of-order data. A job posting dated three weeks ago might arrive today; without watermarking and state management, your aggregations become wrong. Frameworks like Spark Structured Streaming or Flink consume from Kafka, manage micro-batch windows and late-event buffers, and write idempotently to Delta/Iceberg using transaction IDs or deduplication keys.

## Practice

**Problem:** You receive job posting events from Kafka with `job_id`, `job_title_short`, `salary_year_avg`, `job_work_from_home`, `job_posted_date`, and `job_location`. Events may arrive out of order or be replayed on failure. You need to upsert them into a Delta table and query the latest state without duplicates.

```sql
-- Create Delta table with primary key for idempotent writes
CREATE TABLE IF NOT EXISTS job_postings_fact (
  job_id STRING,
  job_title_short STRING,
  salary_year_avg DECIMAL(10, 2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location STRING,
  _kafka_offset LONG,
  _processed_at TIMESTAMP
)
USING DELTA
TBLPROPERTIES ('delta.enableChangeDataFeed' = 'true');

-- Upsert logic (Spark SQL or PySpark DataFrame API)
MERGE INTO job_postings_fact AS target
USING (
  SELECT DISTINCT ON (job_id) * 
  FROM kafka_stream_view  -- Kafka micro-batch
  ORDER BY job_id, _kafka_offset DESC
) AS source
ON target.job_id = source.job_id
WHEN MATCHED AND source._kafka_offset > target._kafka_offset THEN
  UPDATE SET 
    job_title_short = source.job_title_short,
    salary_year_avg = source.salary_year_avg,
    job_work_from_home = source.job_work_from_home,
    job_posted_date = source.job_posted_date,
    job_location = source.job_location,
    _kafka_offset = source._kafka_offset,
    _processed_at = CURRENT_TIMESTAMP
WHEN NOT MATCHED THEN
  INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, 
          job_posted_date, job_location, _kafka_offset, _processed_at)
  VALUES (source.job_id, source.job_title_short, source.salary_year_avg, 
          source.job_work_from_home, source.job_posted_date, source.job_location, 
          source._kafka_offset, CURRENT_TIMESTAMP);
```

## Notes

- **Deduplication key matters:** Track Kafka offset, event ID, or sequence number to reject replayed messages; MERGE with offset comparison is safer than DROP DUPLICATES alone.
- **Schema evolution:** Both Delta and Iceberg support adding columns without rewriting; use `.option("mergeSchema", "true")` in PySpark to auto-evolve on schema mismatches from Kafka schema registry.
- **Late arrivals and watermarking:** Set a watermark on `job_posted_date` if you care about event time; events older than the watermark trigger corrective upserts (not new inserts) via MERGE logic.
- **Checkpoint management:** Spark Structured Streaming tracks offsets in checkpoint directories; losing checkpoints causes reprocessing; store them in cloud object storage (S3, ADLS, GCS) with strict ACLs.
- **Adjacent topics:** Time-series aggregation (windowed counts by `job_location`), Change Data Feed (CDC) for downstream subscriptions, partitioning strategy (e.g., by `job_posted_date` month) for query pushdown.
