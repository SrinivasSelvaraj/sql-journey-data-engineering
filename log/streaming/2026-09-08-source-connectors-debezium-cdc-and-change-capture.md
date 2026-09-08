---
date: 2026-09-08
phase: streaming
topic: Source connectors: Debezium CDC and change capture
---

# Source connectors: Debezium CDC and change capture

*Streaming and distributed processing*

## Concept

Debezium is an open-source CDC (Change Data Capture) platform that reads database transaction logs and converts row-level changes into event streams. It captures INSERT, UPDATE, and DELETE operations as they happen, converting them into ordered change events that flow into message brokers like Kafka. Without CDC, you either batch-poll tables (creating latency and load spikes) or manually instrument application code (fragile, incomplete).

CDC matters when you need a real-time mirror of operational data—data warehousing, analytics pipelines, or keeping multiple systems in sync. The alternative is either stale batch syncs (hours behind) or tight coupling between systems. Debezium decouples the source database from downstream consumers; if a consumer falls behind, the broker buffers events; if you add a new consumer, it can replay from a checkpoint.

What breaks without it: you lose ordering guarantees (async application logs aren't ordered by transaction), you miss deletes entirely (batch SELECT never sees what was removed), and you create cascading failures (if one downstream system is slow, you can't slow down ingestion without losing data).

## Practice

**Problem:** You need to sync `job_postings_fact` changes to a real-time analytics engine. New job postings stream in constantly, salaries get corrected, and old postings are marked inactive. Your batch ETL runs every 6 hours but stakeholders need updates within minutes. How do you capture and stream only the rows that changed?

```sql
-- Debezium connector configuration (JSON)
-- Captures changes from job_postings_fact into Kafka topic "job_postings.changes"
{
  "name": "job_postings_cdc",
  "config": {
    "connector.class": "io.debezium.connector.mysql.MySqlConnector",
    "database.hostname": "prod-db",
    "database.user": "debezium_user",
    "database.password": "***",
    "database.server.id": "1",
    "database.server.name": "job_postings_server",
    "table.include.list": "analytics.job_postings_fact",
    "plugin.name": "pgoutput",
    "publication.name": "job_postings_pub",
    "topic.prefix": "job_postings"
  }
}

-- Kafka topic structure (one event per row change):
-- Key: {"job_id": 12345}
-- Value: {
--   "before": {"job_id": 12345, "job_title_short": "Data Analyst", ...},
--   "after": {"job_id": 12345, "job_title_short": "Senior Data Analyst", "salary_year_avg": 95000, ...},
--   "op": "u",
--   "ts_ms": 1699564800000
-- }

-- Consumer: merge changes into analytics warehouse
MERGE INTO analytics.job_postings_snapshot tgt
USING kafka_stream.job_postings_changes src
ON tgt.job_id = src.after.job_id
WHEN MATCHED AND src.op = 'u' THEN 
  UPDATE SET job_title_short = src.after.job_title_short, 
             salary_year_avg = src.after.salary_year_avg
WHEN MATCHED AND src.op = 'd' THEN DELETE
WHEN NOT MATCHED AND src.op IN ('c', 'u') THEN 
  INSERT VALUES (src.after.*);
```

## Notes

- **Ordering caveat:** Debezium guarantees order *per partition key* (e.g., per job_id), not globally. If the same job is updated on two database replicas, events may arrive out of order; use `ts_ms` to reorder on consume.
- **Snapshot mode:** On first run, Debezium takes a snapshot of the entire table before tailing the log. For large tables this can be slow; use `snapshot.mode: "initial"` or `"when_needed"` to control when snapshots occur.
- **Schema evolution risk:** If you add a column to `job_postings_fact`, Debezium emits it immediately in new events but old events lack it. Downstream consumers must handle nullable fields and use Avro/Protobuf schema registries, not just raw JSON.
- **Replication lag:** CDC is near real-time but not instant. Monitor `ts_ms` and compare to `current_timestamp` in the consumer to expose lag; if lag exceeds your SLA, scale up broker partitions or add parallel consumers.
- **Adjacent topics:** Schema Registry (versioning Kafka messages), exactly-once semantics (idempotent sinks), watermarking and late arrivals (handling out-of-order events in streaming joins).
