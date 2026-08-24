---
date: 2026-08-24
phase: streaming
topic: Debezium for CDC over Kafka
---

# Debezium for CDC over Kafka

*Streaming and distributed processing*

## Concept

Debezium is a distributed platform that captures row-level changes from databases and streams them as events to Apache Kafka. It reads database transaction logs (WAL, binlog, etc.) without requiring application code changes, making it ideal for keeping data warehouses, caches, and search indexes synchronized with transactional systems in near real-time. Debezium connectors (MySQL, PostgreSQL, Oracle, SQL Server, MongoDB) extract INSERT, UPDATE, DELETE operations and emit them as ordered events per table partition, preserving causality within a single resource.

Without CDC (Change Data Capture) via Debezium, you're forced to batch-poll entire tables periodically, missing intermediate states, struggling with late-arriving updates, and creating unnecessary load on source systems. When job postings are updated (salary correction, location change) or soft-deleted, a polling approach either re-ingests unchanged data wastefully or misses the change window entirely. Debezium ensures every mutation reaches your streaming pipeline within milliseconds and arrives in Kafka topics where downstream consumers can replay, filter, and join against other streams deterministically.

## Practice

**Problem:** Track all salary corrections on job postings in real-time. When a job's `salary_year_avg` is updated, you need to know the old value, new value, and timestamp of change to audit compensation changes and trigger alerts if salary drops.

```sql
-- Debezium emits change events to Kafka topic: job_postings_fact-cdc
-- Each event has: before, after, op (c/u/d), ts_ms, source

SELECT 
  job_id,
  CAST(before['salary_year_avg'] AS INT) AS old_salary,
  CAST(after['salary_year_avg'] AS INT) AS new_salary,
  (CAST(after['salary_year_avg'] AS INT) - CAST(before['salary_year_avg'] AS INT)) AS salary_delta,
  CAST(ts_ms AS TIMESTAMP) AS change_timestamp,
  CASE 
    WHEN op = 'u' AND (CAST(after['salary_year_avg'] AS INT) < CAST(before['salary_year_avg'] AS INT))
    THEN 'ALERT_SALARY_DROP'
    ELSE 'OK'
  END AS event_type
FROM kafka_topic('job_postings_fact-cdc')
WHERE op = 'u' AND before['salary_year_avg'] IS NOT NULL
EMIT CHANGES;
```

## Notes

- **Schema evolution trap:** Debezium includes schema in headers (Confluent Schema Registry integration); if the source table adds a column, the before/after structures change shape—validate downstream consumers handle new/missing fields gracefully.
- **Ordering guarantees:** Events for the same `job_id` arrive in one Kafka partition; use that partition key. Cross-partition order is *not* guaranteed—don't assume global sequence.
- **Snapshot + incremental:** First run does a table snapshot (bulk export); enable `snapshot.mode: initial` to capture existing rows. Subsequent restarts resume from log offset, not re-snapshot.
- **Dual-write risk:** If you update the source DB *and* write to Kafka manually elsewhere, Debezium may conflict or create duplication. Treat CDC as single source of truth for mutation events.
- **Connective tissue:** Pairs naturally with Kafka Streams, Flink, or ksqlDB for stateful joins (enriching job postings with historical salary ranges), and feeds into event stores, data lakes (S3 via Kafka Connect Sink), and OLAP systems (Snowflake, BigQuery).
