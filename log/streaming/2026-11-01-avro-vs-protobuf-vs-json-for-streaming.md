---
date: 2026-11-01
phase: streaming
topic: Avro vs Protobuf vs JSON for streaming
---

# Avro vs Protobuf vs JSON for streaming

*Streaming and distributed processing*

## Concept

Avro, Protobuf, and JSON are serialization formats used in streaming pipelines, but they solve different problems. JSON is human-readable and schema-optional, making it easy to start with but inefficient—verbose payloads waste network bandwidth and storage. Avro and Protobuf are binary formats with mandatory schemas; they compress data 5–10x better and catch schema violations early, critical when processing unbounded streams where a single malformed record can cascade failures downstream.

The choice matters most when you're building real-time pipelines where latency and throughput directly impact cost and user experience. JSON works for low-volume, exploratory data; Avro dominates in Kafka ecosystems (Confluent Schema Registry integration), while Protobuf excels when you need language-agnostic, backward-compatible services (gRPC). Without a schema layer, streaming systems become fragile—a producer adding a field, renaming a column, or changing a type will silently corrupt downstream consumers or cause silent data loss.

In streaming, you can't reprocess history easily, so schema evolution (adding optional fields, removing deprecated ones) must be defined upfront. Avro and Protobuf enforce this; JSON leaves it to convention. For job posting streams arriving unordered and out-of-order, a malformed salary or missing job_id in JSON might go undetected until aggregation fails hours later.

## Practice

**Problem:** You're streaming job postings to Kafka. A producer occasionally sends `salary_year_avg` as a string instead of an integer, and sometimes omits `job_location` entirely. With JSON, consumers downstream crash or produce incorrect aggregates. Define an Avro schema that enforces types and handles missing location gracefully.

```sql
-- Avro schema (represented as JSON, stored in Schema Registry)
{
  "type": "record",
  "name": "JobPostingFact",
  "namespace": "com.jobs",
  "fields": [
    {"name": "job_id", "type": "string"},
    {"name": "job_title_short", "type": "string"},
    {"name": "salary_year_avg", "type": ["null", "int"], "default": null},
    {"name": "job_work_from_home", "type": "boolean"},
    {"name": "job_posted_date", "type": "string"},
    {"name": "job_location", "type": ["null", "string"], "default": null}
  ]
}

-- Consumer (Kafka + Avro deserializer) will:
-- 1. Reject any message where salary_year_avg is not int or null → producer error caught immediately
-- 2. Accept job_location as null → downstream logic uses COALESCE(job_location, 'Remote') safely
-- 3. Enforce all fields present (job_id, job_title_short, job_work_from_home, job_posted_date are required)
```

## Notes

- **JSON pitfall**: tempting to skip schema definition, but unstructured streams inevitably diverge; enforce schema even for JSON (e.g., JSON Schema) or migrate to Avro early.
- **Avro vs Protobuf trade-off**: Avro is tightly integrated with Hadoop/Kafka ecosystems; Protobuf is more portable but Schema Registry support is less mature.
- **Schema evolution**: Avro supports forward/backward compatibility via default values and union types (`["null", "int"]`); test schema migrations in staging before deploying to production.
- **Serialization size matters in streams**: at scale (1M events/sec), JSON overhead compounds; Avro typically reduces message size 5–10x, lowering Kafka storage and network costs.
- **Related**: connects to schema versioning strategies, data contracts between teams, and dead-letter queues for handling schema-incompatible messages gracefully.
