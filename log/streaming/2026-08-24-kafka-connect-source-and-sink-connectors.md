---
date: 2026-08-24
phase: streaming
topic: Kafka Connect: source and sink connectors
---

# Kafka Connect: source and sink connectors

*Streaming and distributed processing*

## Concept

Kafka Connect is a framework for reliably moving data between Kafka and external systems via reusable connectors. **Source connectors** ingest data from systems (databases, APIs, files) into Kafka topics; **sink connectors** export data from Kafka topics to destinations (data warehouses, databases, search engines). This decouples data producers from consumers and eliminates the need to write custom integration code for each system pair.

Kafka Connect matters because streaming pipelines often need to continuously sync data from operational systems into analytics platforms without building point-to-point integrations. Without it, you'd write consumers that parse records and manually handle failures, schema evolution, and exactly-once semantics—expensive and fragile. Connect handles distributed task scheduling, fault tolerance, and offset management automatically, so you define *what* to move (configuration) rather than *how*.

It breaks when your source system cannot provide incremental change detection (e.g., no timestamp or ID column for CDC), when your sink lacks idempotency (duplicate writes cause corruption), or when connector task parallelism exceeds topic partitions—causing uneven load and rebalancing storms.

## Practice

**Problem:** You need to stream job postings from a PostgreSQL table into Kafka topic `job_postings`, then sink those records into Elasticsearch for real-time search. The table updates frequently with new postings and salary corrections. Design the connector configuration and verify offset tracking works correctly.

```sql
-- Source: PostgreSQL JDBC Connector (incrementally pulls rows where job_posted_date or updated_at > last offset)
-- Configuration snippet (JSON):
{
  "name": "postgres-job-postings-source",
  "config": {
    "connector.class": "io.confluent.connect.jdbc.source.JdbcSourceConnector",
    "connection.url": "jdbc:postgresql://localhost:5432/hr_db",
    "connection.user": "kafka_user",
    "query": "SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location, updated_at FROM job_postings_fact WHERE updated_at > ? ORDER BY updated_at ASC",
    "topic.prefix": "job_postings",
    "timestamp.column.name": "updated_at",
    "incrementing.column.name": "job_id",
    "mode": "timestamp+incrementing",
    "poll.interval.ms": 5000,
    "tasks.max": 2
  }
}

-- Sink: Elasticsearch Connector (writes to index with job_id as document _id for idempotency)
{
  "name": "job-postings-elasticsearch-sink",
  "config": {
    "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
    "connection.url": "http://elasticsearch:9200",
    "topics": "job_postings",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "io.confluent.connect.json.JsonConverter",
    "type.name": "_doc",
    "document.id.strategy": "com.example.JobIdStrategy",
    "tasks.max": 3
  }
}

-- Verify offsets are tracked (Kafka CLI):
-- kafka-consumer-groups --bootstrap-server localhost:9092 --group connect-cluster --describe
-- Offsets should advance as source connector polls and sink connector commits.
```

## Notes

- **Idempotency trap:** Sink connectors must deduplicate writes (via unique keys or upserts) because Kafka guarantees *at-least-once* delivery, not exactly-once. Elasticsearch and data warehouses handle this via document ID / primary key; some sinks (Kinesis) do not.
- **Schema Registry integration:** Use Avro or Protobuf converters with a Schema Registry for source connectors to enforce schema evolution and downstream compatibility; raw JSON connectors will silently accept breaking changes.
- **Offset management:** Connect stores offsets in a Kafka topic (e.g., `connect-offsets`). Loss of this topic = loss of position and duplicate replay from source. Monitor it and ensure replication factor ≥ 3 in production.
- **Task parallelism:** Source tasks can run in parallel (one per partition or one per table shard); sink tasks must match topic partition count to avoid partition reassignment storms during scaling.
- **Dead letter queues:** Enable error tolerance and route unparseable or rejected records to a separate topic for debugging rather than halting the entire connector.
