---
date: 2026-08-07
phase: sql
topic: String parsing and normalisation
---

# String parsing and normalisation

*SQL for analytics and engineering*

## Concept

String parsing and normalisation in SQL transforms raw text data into consistent, queryable formats. This matters because job titles come in variations ("Sr. Software Engineer", "Senior Software Engineer", "Software Engineer III"), locations include noise ("New York, NY 10001"), and salary fields may have currency symbols or commas. Without normalisation, aggregations fragment across semantically identical values, JOIN operations fail silently, and filtering becomes unreliable.

Normalisation typically involves `TRIM()`, `UPPER()/LOWER()`, `REPLACE()`, `SUBSTRING()`, and regex functions (`REGEXP_REPLACE`, `REGEXP_SUBSTR` depending on dialect). Parsing extracts structured data from unstructured strings—splitting "New York, NY" into city and state, or extracting salary ranges from "80k-120k". Both operations are cheaper done once during ETL, but often necessary in analytics queries when source data quality is poor.

Performance degrades quickly with string functions on large tables: regex operations are CPU-bound, substring extraction on every row of a 10M-row table compounds query time, and repeated parsing in WHERE clauses prevents index usage. The key tradeoff is between query clarity (normalize at query time) and efficiency (normalize once, store normalized values).

## Practice

**Problem:** The `job_postings_fact` table has inconsistent location formats ("new york, ny", "NEW YORK, NY ", "New York,NY"). Write a query that normalises location to title case with consistent spacing, then counts postings by normalised location, but only include locations with at least 50 postings and average salary above $100k.

```sql
WITH normalised_locations AS (
  SELECT
    job_id,
    INITCAP(TRIM(REGEXP_REPLACE(job_location, '\s*,\s*', ', '))) AS location_norm,
    salary_year_avg
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
)
SELECT
  location_norm,
  COUNT(job_id) AS posting_count,
  ROUND(AVG(salary_year_avg), 0) AS avg_salary
FROM normalised_locations
GROUP BY location_norm
HAVING COUNT(job_id) >= 50
  AND AVG(salary_year_avg) > 100000
ORDER BY posting_count DESC;
```

## Notes

- **Regex is dialect-specific:** PostgreSQL uses `~`, Snowflake/BigQuery use `REGEXP_REPLACE()`, MySQL uses `REGEXP`. Always check your platform before writing.
- **TRIM before normalising:** Leading/trailing whitespace breaks GROUP BY aggregations; always strip before UPPER/LOWER or regex operations.
- **Normalise at ETL, not query time:** If you parse strings repeatedly for analytics, create a normalised column during ingestion or use a dbt model layer. Query-time parsing is acceptable for one-off analysis but becomes a maintenance burden at scale.
- **Case sensitivity in JOINs:** Joining on raw strings with inconsistent casing causes silent mismatches. Normalise join keys to the same case on both sides, or use `COLLATE` if your database supports case-insensitive collation.
- **Adjacent skill:** Learn to read EXPLAIN plans to spot where string functions break index usage—full table scans often hide in WHERE clauses with UPPER(column) or SUBSTRING(column).
