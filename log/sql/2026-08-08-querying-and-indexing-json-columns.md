---
date: 2026-08-08
phase: sql
topic: Querying and indexing JSON columns
---

# Querying and indexing JSON columns

*SQL for analytics and engineering*

## Concept

JSON columns in SQL databases (PostgreSQL's `jsonb`, MySQL's `json` type, or semi-structured formats in data warehouses) allow storing nested, hierarchical data without schema changes. Querying these columns requires special operators: `->` and `->>` in PostgreSQL extract values, `JSON_EXTRACT()` in MySQL, and `JSON_QUERY()` / `JSON_VALUE()` in SQL Server. Without proper indexing, queries that filter on JSON fields trigger full table scans—even a moderately large analytics table (millions of rows) becomes unusable. Indexes on JSON paths (e.g., `CREATE INDEX ON table USING gin (column jsonb_path_ops)` in PostgreSQL) are essential to push filtering into the index rather than scanning and parsing every row.

The performance cliff is steep: a query filtering on `WHERE data->>'country' = 'US'` runs in milliseconds on an indexed 10M-row table but takes seconds or minutes without an index. In interview and production contexts, recognizing when a JSON column needs indexing—and knowing the syntax for your specific database—separates performant solutions from time bombs.

## Practice

**Problem:** Given a `job_postings_fact` table where `job_location` is stored as a JSON object (e.g., `{"country": "US", "city": "New York", "state": "NY"}`), write a query to find the average salary for remote jobs posted in the US in the last 30 days, and explain what index would make it fast.

```sql
-- Solution: Query with JSON extraction
SELECT 
  AVG(salary_year_avg) AS avg_salary_us_remote
FROM job_postings_fact
WHERE 
  job_work_from_home = TRUE
  AND (job_location->>'country') = 'US'
  AND job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
  AND salary_year_avg IS NOT NULL;

-- Index to make this performant (PostgreSQL):
CREATE INDEX idx_job_location_country 
  ON job_postings_fact USING gin (job_location jsonb_path_ops);

-- Alternative: B-tree index on extracted column if queries are frequent
ALTER TABLE job_postings_fact 
  ADD COLUMN location_country TEXT GENERATED ALWAYS AS (job_location->>'country') STORED;
CREATE INDEX idx_location_country ON job_postings_fact (location_country);
```

## Notes

- **Operator confusion:** `->` returns JSON type (requires further casting); `->>` returns text. Use `>>` when filtering on string values to avoid type mismatches.
- **GIN vs. B-tree trade-off:** GIN indexes are slower to write but faster for read-heavy JSON queries; B-tree on extracted/generated columns is faster for equality/range but requires schema changes.
- **Query planner blindness:** Without an index, the planner cannot estimate selectivity of JSON predicates—always check `EXPLAIN ANALYZE` output to confirm the index is being used (should show "Index Cond" not "Filter").
- **Null handling:** JSON extraction returns `NULL` for missing keys; this can silently exclude rows. Use `COALESCE()` or explicit null checks if behavior matters.
- **Warehouse-specific syntax:** Snowflake uses `:` notation (`col:field`), BigQuery uses `JSON_EXTRACT()`, and Redshift uses limited JSON support—verify your platform's operators before writing production code.
