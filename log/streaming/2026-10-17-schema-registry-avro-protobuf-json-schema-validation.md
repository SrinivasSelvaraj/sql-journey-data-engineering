---
date: 2026-10-17
phase: streaming
topic: Schema Registry: Avro, Protobuf, JSON schema validation
---

# Schema Registry: Avro, Protobuf, JSON schema validation

*Streaming and distributed processing*

## Concept

A Schema Registry is a centralized repository that stores and versions schemas for your streaming data, ensuring producers and consumers agree on data structure before messages enter a distributed system. In streaming contexts, this is critical because messages arrive continuously and out of order—you cannot afford schema mismatches, silent data loss, or type coercion surprises that only surface hours later. Without it, a producer might send `salary_year_avg` as a string while a consumer expects an integer, or a field might be added upstream with no downstream awareness, leading to deserialization failures or corrupted aggregations.

Avro is schema-on-write and enables compact binary serialization with built-in schema evolution (adding optional fields, renaming with aliases). Protobuf offers similar benefits with a more language-agnostic definition syntax and slightly better performance. JSON Schema works with JSON payloads and is human-readable but less space-efficient. All three integrate with Kafka, Flink, and Spark to enforce validation at ingestion time, making failures visible immediately rather than downstream in analytical queries.

Without schema enforcement, distributed systems degrade silently: late-arriving data with missing fields overwrites aggregations, type mismatches cause NullPointerException in joins, and data lineage becomes impossible to audit. Schema Registry catches these before they poison your data lake.

## Practice

**Problem:** You are consuming `job_postings_fact` from a Kafka topic. A schema change arrives: the producer adds a new optional field `job_skills_required` (array of strings) and renames `job_title_short` to `job_title`. Your consumer must handle old messages (without the new field) and new messages (with renamed column) without crashing or losing data.

```sql
-- Avro schema evolution using Confluent Schema Registry syntax
-- Old schema (version 1):
{
  "type": "record",
  "name": "JobPostingFact",
  "fields": [
    {"name": "job_id", "type": "string"},
    {"name": "job_title_short", "type": "string"},
    {"name": "salary_year_avg", "type": ["null", "int"]},
    {"name": "job_work_from_home", "type": "boolean"},
    {"name": "job_posted_date", "type": "string"},
    {"name": "job_location", "type": "string"}
  ]
}

-- New schema (version 2) with backward compatibility:
{
  "type": "record",
  "name": "JobPostingFact",
  "fields": [
    {"name": "job_id", "type": "string"},
    {"name": "job_title", "type": "string", "aliases": ["job_title_short"]},
    {"name": "salary_year_avg", "type": ["null", "int"]},
    {"name": "job_work_from_home", "type": "boolean"},
    {"name": "job_posted_date", "type": "string"},
    {"name": "job_location", "type": "string"},
    {"name": "job_skills_required", "type": {"type": "array", "items": "string"}, "default": []}
  ]
}

-- Consume both versions in Spark using schema registry:
val df = spark
  .readStream
  .format("kafka")
  .option("kafka.bootstrap.servers", "localhost:9092")
  .option("subscribe", "job_postings_topic")
  .option("kafka.security.protocol", "PLAINTEXT")
  .load()
  .select(from_avro(col("value"), 
    SchemaRegistryClient.fetchLatestSchema("job_postings_topic-value")).alias("data"))
  .select("data.*")

-- Old messages deserialize with job_skills_required = [] (default)
-- New messages deserialize with job_title mapped from job_title_short (alias)
```

## Notes

- **Schema compatibility modes matter**: Backward (old readers accept new data), Forward (new readers accept old data), and Full (both directions). Streaming usually requires Backward to avoid breaking existing consumers mid-deployment.
- **Aliases and defaults are lifelines**: Use `aliases` in Avro/Protobuf to rename fields without losing historical data; always provide `default` values for new fields so old messages don't cause nulls in critical paths.
- **Version management is implicit**: The registry tracks schema versions and embeds a schema ID in each message, so deserialization is deterministic—avoid manual version flags in your payload.
- **Connects to data contracts and observability**: Schema Registry is the enforcement layer for data contracts between teams; pair it with schema lineage tracking (e.g., in Apache Atlas) and monitoring of deserialization errors per schema version to catch breaking changes early.
- **Protobuf shines for gRPC pipelines**: If your streaming system also uses gRPC for request-reply, Protobuf schemas unify both, reducing cognitive load and schema duplication across transport layers.
