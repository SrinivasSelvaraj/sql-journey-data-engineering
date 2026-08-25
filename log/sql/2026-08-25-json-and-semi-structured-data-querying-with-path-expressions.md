---
date: 2026-08-25
phase: sql
topic: JSON and semi-structured data querying with path expressions
---

# JSON and semi-structured data querying with path expressions

*SQL for analytics and engineering*

## Concept

JSON and semi-structured data querying with path expressions allows you to extract, filter, and aggregate nested values from JSON columns without flattening the entire structure. Rather than storing location as a single string, a job posting might store `{"city": "New York", "state": "NY", "country": "US"}` in a single column—path expressions like `location->'city'` or `location['city']` let you query that directly in the WHERE or SELECT clause.

This matters because real-world APIs and data pipelines often deliver nested objects (job requirements, company metadata, salary ranges) as JSON. Without path expressions, you'd either parse everything into separate columns (denormalization) or load the raw JSON into application code. Path expressions keep queries concise and let the database engine handle filtering early, improving performance dramatically when dealing with large semi-structured tables.

Without mastering path expressions, you either over-normalize your schema (creating unnecessary joins), under-utilize filtering (scanning entire JSON blobs in memory), or write fragile string parsing logic. Interview conditions demand you recognize when JSON querying is the right tool and execute it cleanly.

## Practice

**Problem:** Given `job_postings_fact` where `job_location` is stored as JSON (e.g., `{"city": "San Francisco", "state": "CA", "country": "US"}`), find the average salary for Data Engineer roles posted in California, and count how many were remote-eligible.

```sql
SELECT
  COUNT(*) as total_postings,
  COUNT(CASE WHEN job_work_from_home THEN 1 END) as remote_count,
  ROUND(AVG(salary_year_avg), 2) as avg_salary
FROM job_postings_fact
WHERE job_title_short = 'Data Engineer'
  AND job_location->>'state' = 'CA'
  AND salary_year_avg IS NOT NULL;
```

**Note:** The `->>'state'` operator (or `->'state'` then cast to text, depending on your database) extracts the JSON value as text for comparison. If your database is PostgreSQL, use `->>` for text extraction; if BigQuery, use `JSON_EXTRACT_SCALAR(job_location, '$.state')`; if Snowflake, use `job_location:state::string`.

## Notes

- **Operator confusion:** `->'key'` returns JSON type (allows chaining), `->>'key'` returns text/scalar. Know which one you need before casting or filtering.
- **NULL handling in JSON:** Missing keys or null JSON values behave differently; always test with `IS NULL` or `JSON_EXTRACT(field, path) IS NULL` to avoid silent filter failures.
- **Index strategy:** Path expressions can bypass B-tree indexes; create functional or expression indexes on frequently filtered paths (`CREATE INDEX idx_job_location_state ON job_postings_fact ((job_location->>'state'))`) for production performance.
- **Adjacent topics:** UNNEST/explode for arrays within JSON, window functions for ranking within location groups, and understanding explain plans when JSON operators are involved.
- **Revisit:** Test behavior when JSON structure is inconsistent (some records missing the key entirely) and practice casting results to correct types for aggregation functions.
