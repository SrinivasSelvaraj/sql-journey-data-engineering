---
date: 2026-11-07
phase: sql
topic: JSON path expressions: nested document extraction and filtering
---

# JSON path expressions: nested document extraction and filtering

*SQL for analytics and engineering*

## Concept

JSON path expressions enable extraction and filtering of nested data structures directly within SQL queries, avoiding the need for application-layer parsing. Most modern databases (PostgreSQL `jsonb_extract_path()` / `->` operators, BigQuery `JSON_EXTRACT()`, Snowflake `GET_PATH()`) support these natively, making them essential for handling semi-structured data without denormalization. They matter because production systems often store metadata, tags, or user preferences as JSON; querying without path expressions forces you to retrieve entire documents and process them outside SQL, destroying pushdown filtering and increasing memory overhead.

Without JSON path support, you lose query optimization at the database level—filtering on nested fields becomes impossible in the WHERE clause, you retrieve full JSON documents unnecessarily, and you cannot create indexes on nested properties (in some databases). This becomes a performance cliff when dealing with millions of rows where a single nested boolean or numeric field could reduce result sets by 90%.

## Practice

**Problem:** The `job_location` column contains JSON like `{"city":"New York","state":"NY","country":"USA"}`. Extract all remote (work_from_home = true) data analyst positions posted in 2024 where the job location is in the USA, and return the job title, salary, city, and state.

```sql
SELECT 
  job_title_short,
  salary_year_avg,
  job_location->>'city' AS city,
  job_location->>'state' AS state
FROM job_postings_fact
WHERE 
  job_work_from_home = TRUE
  AND EXTRACT(YEAR FROM job_posted_date) = 2024
  AND job_title_short ILIKE '%Data Analyst%'
  AND job_location->>'country' = 'USA'
ORDER BY salary_year_avg DESC;
```

*(PostgreSQL syntax; use `JSON_EXTRACT(job_location, '$.city')` in BigQuery or `GET_PATH(job_location, ['city'])` in Snowflake)*

## Notes

- **Operator choice matters:** `->` returns JSON type; `->>` returns text. Use `->>` when filtering or casting to avoid type coercion delays; use `->` when chaining nested paths.
- **Indexing depth:** Create a generated/virtual column or a partial index on the extracted field for frequent filters: `CREATE INDEX idx_job_location_country ON job_postings_fact((job_location->>'country'))`.
- **NULL handling:** JSON path operators return NULL silently if the key doesn't exist; wrap in `COALESCE()` if you need defaults, or use `jsonb_exists()` / `JSON_EXTRACT_SCALAR()` to validate structure first.
- **Performance trap:** Extracting the same path multiple times in one query is wasteful; use CTEs or subqueries to extract once, then reference the computed column.
- **Adjacent skill:** Understand the difference between `jsonb` (PostgreSQL binary format, faster, supports indexing) and `json` (text format); always choose `jsonb` for production analytics workloads.
