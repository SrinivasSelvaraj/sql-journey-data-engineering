---
date: 2026-08-11
phase: pipelines
topic: ETL vs ELT and what changed to allow ELT
---

# ETL vs ELT and what changed to allow ELT

*Pipelines and orchestration*

## Concept

ETL (Extract, Transform, Load) was the default for decades because storage and compute were expensive. You transformed data *before* loading it into the warehouse, minimizing what you stored and paid for. ELT (Extract, Load, Transform) reverses this: load raw data first, transform it in place using the warehouse's compute. This shift became viable when cloud data warehouses (Snowflake, BigQuery, Redshift) made compute cheap and storage abundant, and when they added powerful SQL engines that could handle transformation at scale without moving data.

The difference matters operationally. ETL pipelines are tightly coupled to transformation logic—if your ETL breaks mid-transform, data is lost or inconsistent. ELT keeps raw data immutable in landing zones; transformations happen in reproducible SQL layers. Failures are easier to diagnose (did the extract fail, or the transform?), and reruns are safer because you're not overwriting source truth.

Without clarity on this distinction, teams often build fragile ETL processes that hide errors in middleware, lack audit trails, or duplicate transformation logic across tools. You end up debugging in three places: the extraction script, the middleware, and the warehouse—instead of just the SQL.

## Practice

**Problem:** Your `job_postings_fact` table is loading data with inconsistent date formats from different job boards, and you have no way to audit which rows came from which source. When salaries look wrong, you can't trace back to the raw extract. You need to add data lineage and make transformations reproducible.

**Solution:** Implement ELT by landing raw data first, then transforming it in clear SQL layers.

```sql
-- Layer 1: Raw landing (load as-is, append only)
CREATE TABLE job_postings_raw (
  source_name STRING,
  raw_payload JSON,
  extracted_at TIMESTAMP,
  _load_id STRING  -- tracks which pipeline run loaded this
);

-- Layer 2: Cleaned (standardize, add lineage)
CREATE TABLE job_postings_cleaned AS
SELECT
  _load_id,
  source_name,
  JSON_EXTRACT_SCALAR(raw_payload, '$.id') AS job_id,
  JSON_EXTRACT_SCALAR(raw_payload, '$.title') AS job_title_short,
  SAFE.INT64(JSON_EXTRACT_SCALAR(raw_payload, '$.salary')) AS salary_year_avg,
  CAST(JSON_EXTRACT_SCALAR(raw_payload, '$.remote') AS BOOL) AS job_work_from_home,
  PARSE_DATE('%Y-%m-%d', JSON_EXTRACT_SCALAR(raw_payload, '$.posted_date')) AS job_posted_date,
  JSON_EXTRACT_SCALAR(raw_payload, '$.location') AS job_location,
  CURRENT_TIMESTAMP() AS transformed_at
FROM job_postings_raw
WHERE extracted_at >= CURRENT_DATE() - 1;

-- Layer 3: Fact table (business logic, deduplication)
CREATE TABLE job_postings_fact AS
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM job_postings_cleaned
QUALIFY ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY transformed_at DESC) = 1;
```

This way: raw data is immutable (audit trail), transformations are version-controlled SQL (reproducible), and each layer can be tested independently.

## Notes

- **Layer naming matters:** Use `_raw` → `_cleaned` → `_fact` naming consistently so future maintainers know the transformation stage and trust level of each table.
- **Idempotency is non-negotiable:** Your transformation SQL must produce identical results when run twice on the same input (use `QUALIFY`, `MERGE`, or `DELETE + INSERT` patterns, never simple `INSERT`).
- **ELT doesn't mean "no transformation before load":** Sometimes you still transform during extraction for size/cost (e.g., filter to last 7 days), but keep the raw data if you can; the tradeoff is explicit, not hidden.
- **Connect to:** data lineage tools (dbt, Collibra), idempotent orchestration (Dagster, dbt Cloud), and the dreaded "schema-on-read" problem where too much raw data makes downstream users slow.
- **Revisit:** partition strategy on raw tables (partition by `extracted_at`, not `job_posted_date`) to avoid full-table scans during incremental loads.
