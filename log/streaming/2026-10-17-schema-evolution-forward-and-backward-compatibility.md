---
date: 2026-10-17
phase: streaming
topic: Schema evolution: forward and backward compatibility
---

# Schema evolution: forward and backward compatibility

*Streaming and distributed processing*

## Concept

Schema evolution is the ability to change a data schema over time while keeping upstream and downstream systems functional. In streaming systems, this is critical because data arrives continuously from producers you cannot pause—you cannot coordinate a schema migration across all sources simultaneously. **Backward compatibility** means new schema versions can read data written by old versions (protecting consumers). **Forward compatibility** means old consumers can safely read data written by new versions (protecting producers from forced upgrades).

Without compatibility guarantees, schema changes break pipelines immediately. A producer adds a required field; old consumers crash. A consumer expects a field that gets renamed; data loss or parsing errors follow. In unbounded streams, you cannot "replay from the start" easily, so breaking changes often mean data is permanently lost or pipelines stay frozen on old schemas, blocking legitimate evolution.

The practical solution is **additive, optional changes**: add new columns with defaults, mark old columns for deprecation rather than deletion, and use serialization formats (Avro, Protobuf) that explicitly define compatibility modes. Version your schemas, document deprecation timelines, and test consumers against multiple schema versions.

## Practice

**Problem**: The `job_postings_fact` table is consumed by three downstream teams. You need to add a new field `job_salary_currency` (defaulting to 'USD') and rename `job_work_from_home` to `job_remote_eligible` without breaking existing consumers or losing data in flight.

```sql
-- Backward compatible: add new column with default, old producers still work
ALTER TABLE job_postings_fact 
ADD COLUMN job_salary_currency VARCHAR(3) DEFAULT 'USD';

-- Forward compatible: keep old column as view/alias, deprecate gradually
ALTER TABLE job_postings_fact 
ADD COLUMN job_remote_eligible BOOLEAN;

-- Backfill and sync both columns during transition window
UPDATE job_postings_fact 
SET job_remote_eligible = job_work_from_home 
WHERE job_remote_eligible IS NULL;

-- Mark old column deprecated in schema metadata/documentation
-- After 6-month notice period, drop: ALTER TABLE job_postings_fact DROP COLUMN job_work_from_home;

-- For Avro/Protobuf schemas, define like this:
-- {
--   "name": "job_postings_fact",
--   "fields": [
--     {"name": "job_remote_eligible", "type": "boolean", "default": false},
--     {"name": "job_work_from_home", "type": ["null", "boolean"], "default": null} -- deprecated
--   ]
-- }
```

## Notes

- **Mistake**: Deleting or renaming columns immediately; in streaming, in-flight records still use the old schema and fail on arrival. Always add a deprecation window (90–180 days).
- **Mistake**: Making new columns required without defaults; old producers cannot satisfy the constraint and start failing on writes.
- **Schema registry**: Tools like Confluent Schema Registry enforce compatibility rules at publish time, catching breaking changes before they propagate.
- **Related**: Idempotency and late-arriving data go hand-in-hand with schema evolution—if a record arrives with an old schema after the migration, your system must still process it correctly.
- **Revisit**: When dealing with nested schemas (structs, arrays) or union types, compatibility becomes more complex; test edge cases around null handling and type coercion.
