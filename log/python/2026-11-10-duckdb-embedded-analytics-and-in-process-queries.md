---
date: 2026-11-10
phase: python
topic: DuckDB: embedded analytics and in-process queries
---

# DuckDB: embedded analytics and in-process queries

*Python for data engineering*

## Concept

DuckDB is an embedded SQL database engine optimized for analytical queries on structured data, running in-process within Python without a separate server. Unlike SQLite (row-oriented), DuckDB is columnar and vectorized, making it orders of magnitude faster for aggregations, filtering, and joins on larger datasets. It matters in data pipelines because it lets you write typed, testable SQL logic directly against in-memory or file-backed data—no Pandas gymnastics, no orchestration overhead, no network latency.

What breaks without it: you end up writing brittle loops or unclear Pandas transformations that are hard to test in isolation, or you spin up PostgreSQL/Snowflake for development when you just need to validate a transformation locally. DuckDB fits the gap between "quick local analysis" and "production warehouse"—it's your testing and prototyping ally, and it's fast enough to handle multi-GB datasets on a laptop.

## Practice

**Problem:** You have a job_postings_fact table and need to identify which job titles have median salaries above the 75th percentile of all salaries, excluding remote-only postings. Return title, median salary, and count of non-remote postings.

```sql
WITH salary_percentiles AS (
  SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary_year_avg) AS p75
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
),
title_stats AS (
  SELECT
    job_title_short,
    MEDIAN(salary_year_avg) AS median_salary,
    COUNT(*) AS posting_count
  FROM job_postings_fact
  WHERE job_work_from_home = FALSE
    AND salary_year_avg IS NOT NULL
  GROUP BY job_title_short
)
SELECT
  ts.job_title_short,
  ts.median_salary,
  ts.posting_count
FROM title_stats ts
CROSS JOIN salary_percentiles sp
WHERE ts.median_salary > sp.p75
ORDER BY ts.median_salary DESC;
```

## Notes

- **NULL handling is explicit in DuckDB**: `IS NOT NULL` guards prevent silent failures; use `COALESCE` or `TRY_CAST` to handle bad input types at query time, not in Python cleanup.
- **Use `rel.pl()` for Polars integration**: DuckDB plays well with Polars DataFrames, letting you move between SQL and expressive Polars syntax without serialization overhead.
- **Test queries in isolation**: wrap DuckDB queries in functions with type hints (`-> pl.DataFrame`) and unit test them against small fixture tables before connecting to real pipelines.
- **Columnar storage (Parquet) + DuckDB = fast**: instead of reading CSV into memory, use DuckDB to query Parquet directly—filtering and aggregation happen at storage read time.
- **Adjacent topic**: learn about DuckDB's `CREATE TEMP TABLE AS` for ephemeral test fixtures and `EXPLAIN` for query plans when debugging slow analytical logic.
