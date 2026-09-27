---
date: 2026-09-27
phase: streaming
topic: Flink savepoint versioning and schema evolution
---

# Flink savepoint versioning and schema evolution

*Streaming and distributed processing*

## Concept

A **savepoint** in Apache Flink is a consistent snapshot of an application state at a specific point in time. Versioning savepoints becomes critical when your job logic or data schema changes: you need to know which version of state was captured, and whether new code can deserialize old state without corruption. Schema evolution in streaming means adding fields, changing types, or removing columns—all while processing never stops. Without explicit versioning, redeploying a job with schema changes often causes deserialization failures, data loss, or silent corruption.

The problem compounds because streaming jobs run 24/7; you cannot simply reprocess history like batch pipelines. A savepoint taken under schema v1 must be intelligible to code compiled for schema v2. Flink's state serialization (via TypeInformation or custom serializers) locks in field order and types; if you add a nullable field without updating the serializer, recovery will fail or drop data. Versioning forces you to explicit about what changed and how to bridge old and new state.

## Practice

**Problem:** Your job reads job postings and enriches them. You've been storing state keyed by `job_id`, tracking the last 5 salary figures per job. Now you need to add a new field `salary_currency` (string, default "USD") to your state record. You have a savepoint from yesterday. How do you safely redeploy without losing the historical salary data?

```sql
-- Before: State class (Scala/Java pseudocode translated to logical schema)
-- StateRecord v1: (job_id, last_5_salaries: List[Double])

-- After: Add currency tracking
-- StateRecord v2: (job_id, last_5_salaries: List[Double], salary_currency: String = "USD")

-- Solution: Use a custom KryoSerializer with versioning
-- 1. Wrap state in a versioned envelope
-- 2. In your state descriptor, specify a custom serializer that detects old format
-- 3. Migration logic on read:

-- Pseudo-code in your Flink job:
-- val stateDescriptor = new ValueStateDescriptor[SalaryState](
--   "salary_state",
--   classOf[SalaryState]
-- )
-- stateDescriptor.initializeSerializerUnlessSet(env.getExecutionConfig)
-- 
-- // Custom Kryo serializer registration:
-- env.getConfig.registerTypeWithKryoSerializer(
--   classOf[SalaryState],
--   classOf[VersionedSalaryStateSerializer]
-- )
--
-- // VersionedSalaryStateSerializer.read():
-- val version = input.readInt()  // Read version byte first
-- version match {
--   case 1 =>
--     val jobId = input.readLong()
--     val salaries = readDoubleList(input)
--     SalaryState(jobId, salaries, "USD")  // Default currency for old records
--   case 2 =>
--     val jobId = input.readLong()
--     val salaries = readDoubleList(input)
--     val currency = input.readString()
--     SalaryState(jobId, salaries, currency)
-- }

-- After redeployment:
-- - Savepoint restored with v1 records converted on-the-fly to v2
-- - No data loss; all salaries retained, currency defaults to USD
-- - Subsequent state writes use v2 format
```

## Notes

- **Mistake:** Changing state classes without updating the serializer or providing a migration strategy; Flink will throw `ClassNotFoundException` or deserialize garbage. Always increment a version byte/enum at the start of your serialized state.
- **Mistake:** Assuming nullable fields are free; if you add a non-optional field to an existing state class without a default, old savepoints will fail to deserialize. Wrap new fields in `Option` or use custom serializers with defaults.
- **Adjacent topic:** State backend choice (RocksDB vs. in-memory) affects serialization overhead; RocksDB requires Kryo or custom serializers and makes versioning mistakes more visible because state lives on disk.
- **Adjacent topic:** Flink's Type Extraction and TypeSerializerConfigSnapshot classes provide reflection-based hints; for complex schemas, explicit custom serializers are more robust than relying on Flink's auto-detection.
- **Revisit:** Test savepoint recovery in CI/CD; create old-format savepoints, update code, then verify restore succeeds and produces correct results before production deployment.
