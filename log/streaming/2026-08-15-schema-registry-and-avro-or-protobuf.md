---
date: 2026-08-15
phase: streaming
topic: Schema registry and Avro or Protobuf
---

# Schema registry and Avro or Protobuf

*Streaming and distributed processing*

## Concept

A schema registry is a centralized system that stores and versions schemas (Avro, Protobuf, or JSON Schema) for streaming data. In streaming pipelines, data arrives continuously from multiple producers without guaranteed order, so consumers need to know *upfront* how to deserialize each message. Without a schema registry, each message must carry its full schema, bloating payload size and making evolution fragile. With one, producers register a schema once, attach only a schema ID to each message, and consumers fetch the schema from the registry—reducing network overhead and enabling coordinated schema changes.

Avro and Protobuf are binary serialization formats optimized for streaming. Avro is self-describing (includes field names) and integrates tightly with Hadoop/Kafka ecosystems; Protobuf is more compact and language-agnostic, favored by gRPC and large-scale systems. Both support versioning rules (adding optional fields, removing fields with defaults) so old producers and new consumers can coexist during rolling deployments—critical in systems where you cannot stop all data sources at once.

Without schema governance, a careless producer change (renaming a field, changing a type) silently corrupts downstream consumers: a Kafka consumer parsing an integer as a string, or missing a newly required field entirely. A schema registry enforces contracts, rejects incompatible schemas, and makes breaking changes visible before they propagate.

## Practice

**Problem:** Your job_postings_fact topic has been produced by an old system that publishes salary_year_avg as a string (e.g., "75000"). You are onboarding a new producer that sends it as an integer. Consumers in your warehouse expect a consistent numeric type. How do you manage this transition safely?

```sql
-- Schema Registry: Define the authoritative Avro schema for job_postings_fact
{
  "type": "record",
  "name": "JobPostingsFact",
  "namespace": "data.jobs",
  "fields": [
    {"name": "job_id", "type": "int"},
    {"name": "job_title_short", "type": "string"},
    {"name": "salary_year_avg", "type": "long"},  -- INTEGER canonical form
    {"name": "job_work_from_home", "type": "boolean"},
    {"name": "job_posted_date", "type": {"type": "int", "logicalType": "date"}},
    {"name": "job_location", "type": "string"}
  ]
}

-- In Kafka Connect or your producer code:
-- Old producer: register schema version 1 with salary_year_avg as string (BACKWARD compatible)
-- New producer: register schema version 2 with salary_year_avg as long (FORWARD compatible with v1 if field is optional in v1)
-- Use BACKWARD_TRANSITIVE compatibility mode: new consumers can read old messages via type coercion

-- Consumer (Spark/SQL) reads from schema registry automatically:
-- SELECT salary_year_avg (now guaranteed long type) FROM job_postings_fact WHERE salary_year_avg > 100000
```

## Notes

- **Common mistake:** Treating schema changes as "just data issues." Schema incompatibility breaks deserialization before the message reaches your transformation logic; test schema migrations in staging with both old and new producers running simultaneously.
- **Compatibility modes matter:** BACKWARD allows new consumers to read old messages; FORWARD allows old consumers to read new messages; FULL requires both. Choose based on your deployment strategy (blue-green vs. rolling).
- **Adjacent topic:** Data contracts and schema-first development—pair schema registry with documentation (e.g., what salary_year_avg means, null handling, expected ranges) to prevent semantic mismatches.
- **Revisit:** The difference between schema validation (registry rejects bad schemas) and data validation (consumers check business rules like salary > 0); they are separate concerns.
- **Protobuf vs. Avro trade-off:** Protobuf is smaller and faster; Avro is easier to evolve and debug (human-readable field names in binary). For financial data, Protobuf; for analytics pipelines with frequent schema changes, Avro.
