---
date: 2026-09-12
phase: sql
topic: Array and struct flattening in nested schemas
---

# Array and struct flattening in nested schemas

*SQL for analytics and engineering*

## Concept

Nested schemas—arrays and structs—are common in modern data warehouses (Snowflake, BigQuery, Redshift Spectrum) but require explicit flattening to perform analytics. A struct is a named composite type (like a row within a column); an array contains multiple values of the same type. Without flattening, you cannot filter on nested fields, join on them, or aggregate them meaningfully. Flattening converts a single row with nested data into multiple rows (for arrays via `LATERAL FLATTEN` or `UNNEST`) or extracts struct fields into top-level columns (via dot notation or `GET_JSON_OBJECT`).

When data arrives from APIs, logs, or semi-structured sources, it often lands as JSON or Avro with deeply nested hierarchies. Querying these directly either returns the raw object (useless for filtering) or fails entirely. The choice of flattening strategy—`LATERAL FLATTEN`, `UNNEST`, `EXPLODE`, or dot-notation extraction—depends on your warehouse and schema depth. Performance matters: unnecessary flattening can explode row counts and balloon query cost.

## Practice

**Problem:** The job_postings_fact table has a `job_location` column stored as a struct with fields `city`, `country`, and `remote_region_id` (array). You need to count job postings by country and list all remote regions available per country, without duplicates.

```sql
-- Flatten struct and array to get country-level aggregation with remote regions
WITH flattened_locations AS (
  SELECT
    job_id,
    job_title_short,
    job_location.country AS country,
    remote_region_id
  FROM job_postings_fact,
    LATERAL FLATTEN(INPUT => job_location.remote_region_id) f
  WHERE job_location.country IS NOT NULL
)
SELECT
  country,
  COUNT(DISTINCT job_id) AS posting_count,
  ARRAY_AGG(DISTINCT remote_region_id IGNORE NULLS) AS regions_list
FROM flattened_locations
GROUP BY country
ORDER BY posting_count DESC;
```

**Alternative (BigQuery syntax):**
```sql
SELECT
  job_location.country AS country,
  COUNT(DISTINCT job_id) AS posting_count,
  ARRAY_AGG(DISTINCT region IGNORE NULLS) AS regions_list
FROM job_postings_fact,
  UNNEST(job_location.remote_region_id) AS region
WHERE job_location.country IS NOT NULL
GROUP BY country
ORDER BY posting_count DESC;
```

## Notes

- **Row explosion risk:** `LATERAL FLATTEN` or `UNNEST` on a large array can multiply row count dramatically before aggregation; always filter early and aggregate to avoid memory/cost blowup.
- **Null handling:** Struct fields and array elements can be NULL; explicitly check and use `IGNORE NULLS` in aggregate functions to avoid silent data loss.
- **Dot notation vs. extraction:** Snowflake and BigQuery allow direct dot notation (`struct.field`) in SELECT, but nested filtering often requires `LATERAL FLATTEN` for readability and performance.
- **Adjacent topics:** semi-structured data handling (JSON parsing), denormalization trade-offs, and columnar vs. nested storage; revisit when optimizing schemas for recurring analytical queries.
- **Interview note:** Explain *why* you flatten (correctness + performance), not just *how*; discuss whether to flatten in a CTE or schema layer and justify row-count impact.
