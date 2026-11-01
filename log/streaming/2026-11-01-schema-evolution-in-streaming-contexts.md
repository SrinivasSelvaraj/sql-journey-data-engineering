---
date: 2026-11-01
phase: streaming
topic: Schema evolution in streaming contexts
---

# Schema evolution in streaming contexts

*Streaming and distributed processing*

## Concept

Schema evolution in streaming contexts means handling changes to data structure while records continuously flow through a pipeline. Unlike batch processing where you can pause and migrate all data at once, streaming systems process unbounded data that arrives out of order and never stops. A new field added upstream (e.g., a job posting now includes `job_salary_currency`), a renamed column, or a removed field can break downstream consumers if the pipeline doesn't accommodate these changes gracefully.

Without schema evolution strategy, you face two painful choices: either reject valid new records that don't match the old schema (data loss), or crash the pipeline when unexpected fields arrive. In real systems, upstream producers evolve schemas constantly—adding optional fields for new features, deprecating old ones. Your streaming job must continue processing without manual intervention, even as the schema shifts beneath it.

The key insight is distinguishing *additive* changes (new optional fields, backward-compatible) from *breaking* changes (renamed columns, deleted required fields). Tools like schema registries (Confluent Schema Registry, AWS Glue Schema Registry) version schemas and enforce compatibility rules, while formats like Avro and Protobuf embed schema with data, letting consumers adapt automatically.

## Practice

**Problem:** Your job_postings_fact stream suddenly includes a new optional field `job_salary_currency` (defaulting to 'USD'). Existing records lack this field. Downstream dashboards query both old and new records. How do you handle this without data loss or pipeline failure?

```sql
-- Define a view that handles schema evolution with COALESCE and defaults
CREATE OR REPLACE VIEW job_postings_normalized AS
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  COALESCE(job_salary_currency, 'USD') AS job_salary_currency,
  _schema_version,  -- track which schema version produced this record
  _ingestion_timestamp
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY;

-- Alternatively, use a CASE statement to handle multiple schema versions
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  CASE 
    WHEN _schema_version >= 2 THEN job_salary_currency
    ELSE 'USD'  -- default for records from schema v1
  END AS job_salary_currency
FROM job_postings_fact;
```

## Notes

- **Additive vs. breaking changes:** Always make new fields optional with sensible defaults; never remove or rename columns without versioning. Schema registries enforce this at write time.
- **Schema versioning metadata:** Include `_schema_version` or `_metadata` columns in your raw stream so downstream logic can conditionally handle old and new data shapes.
- **Avro/Protobuf over JSON:** Strongly typed schemas with built-in versioning beat schemaless JSON for streaming; they catch incompatibilities early and compress better.
- **Connector configuration:** Kafka Connect, Spark Streaming, and Flink all have schema registry integrations; configure them to fetch the latest compatible schema, not fail on mismatch.
- **Test against future schemas:** In your CI/CD, simulate adding a new optional field or renaming a column; verify your pipeline and downstream queries survive without manual fixes.
