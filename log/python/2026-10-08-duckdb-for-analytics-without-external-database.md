---
date: 2026-10-08
phase: python
topic: DuckDB for analytics without external database
---

# DuckDB for analytics without external database

*Python for data engineering*

## Concept

DuckDB is an embedded SQL database optimized for analytical queries on structured data, running in-process without requiring a separate server. Unlike SQLite (designed for transactional workloads), DuckDB excels at columnar operations—filtering, aggregating, and joining large datasets directly in Python pipelines. This matters because analytics code often needs to transform data before loading to a warehouse, and DuckDB lets you write typeable SQL queries (via `.sql()` or `.relation()`) that are far easier to test and validate than pandas manipulations strung together with method chaining.

The risk without it: pandas workflows become unreadable (`df.groupby(['col1','col2']).agg(...).reset_index()`), lose SQL's declarative clarity, and hide performance cliffs. Type hints break down because intermediate DataFrames lack schema contracts. Testing becomes brittle—you're testing implementation details (column order, index state) rather than logical correctness. DuckDB forces schema awareness and SQL explicitness into your pipeline code.

## Practice

**Problem:** Extract jobs posted in the last 90 days, filter for remote positions with salary > $100k, and calculate median salary by job title. Return only titles with 5+ postings.

```sql
SELECT 
  job_title_short,
  COUNT(*) AS posting_count,
  MEDIAN(salary_year_avg) AS median_salary
FROM job_postings_fact
WHERE 
  job_work_from_home = true
  AND salary_year_avg > 100000
  AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY job_title_short
HAVING COUNT(*) >= 5
ORDER BY median_salary DESC;
```

## Notes

- **Schema enforcement:** Always define or inspect table schema upfront (`.describe()`, `.info()`). Mismatched types (string vs. date) silently fail downstream and are hard to debug in pandas.
- **NULL handling matters:** DuckDB respects NULLs in aggregates and comparisons; `salary_year_avg > 100000` excludes NULLs by design. Document this behavior in pipeline code comments.
- **Testability win:** Write queries as functions returning `.to_df()` or `.arrow()`, mock the relation input, assert on the output schema *and* row counts. This beats testing pandas `.apply()` chains.
- **Adjacent topic:** Learn `duckdb.from_df()` and `.to_df()` for bidirectional conversion; use DuckDB for heavy lifting, drop to pandas only for non-tabular operations (e.g., time-series resampling, custom functions).
- **Performance cliff:** DuckDB is fast on large in-memory datasets but not a replacement for Postgres/BigQuery for persistent storage. Use it as a *staging layer* in pipelines, not the source of truth.
