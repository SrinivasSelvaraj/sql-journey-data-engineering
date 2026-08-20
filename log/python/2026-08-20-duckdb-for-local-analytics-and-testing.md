---
date: 2026-08-20
phase: python
topic: DuckDB for local analytics and testing
---

# DuckDB for local analytics and testing

*Python for data engineering*

## Concept

DuckDB is an embedded SQL database optimized for analytical queries on local datasets, serving as a lightweight alternative to PostgreSQL or Snowflake for development and testing. Unlike SQLite (which prioritizes transactional correctness), DuckDB is built for OLAP workloads—fast aggregations, joins, and transformations on structured data without network overhead. In data engineering pipelines, it eliminates the friction of spinning up a database service just to validate your ETL logic or test edge cases before pushing to production.

It matters most when you need reproducible, deterministic testing environments. A pipeline that works against live data might fail catastrophically on malformed input, NULL distributions, or boundary cases. DuckDB lets you build realistic test datasets locally, run your transformations end-to-end, and catch bugs before they reach cloud warehouses where they cost money and visibility. The Python integration via `duckdb.sql()` and `duckdb.from_df()` makes it natural to test pandas-to-SQL handoffs and validate type coercion.

Without local testing against realistic schemas, you ship pipelines that fail silently on NULL salary values, miss date format inconsistencies, or assume columns exist when they don't. DuckDB makes that friction visible in development, not in production.

## Practice

**Problem:** You're building a pipeline that filters remote job postings earning >$100k annually and calculates average salary by job title. Your code assumes salary_year_avg is always present and numeric, and that job_posted_date is parseable. How do you test that your transformation handles NULLs, type mismatches, and missing columns gracefully?

```sql
-- Create test table with edge cases
CREATE TABLE job_postings_fact AS
SELECT * FROM (
  VALUES
    (1, 'Data Engineer', 120000, true, '2024-01-15'::DATE, 'Remote'),
    (2, 'Analyst', NULL, false, '2024-01-20'::DATE, 'New York'),
    (3, 'ML Engineer', 95000, true, '2024-02-01'::DATE, 'Remote'),
    (4, 'Data Scientist', 150000, true, NULL, 'San Francisco')
) AS t(job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location);

-- Test: filter remote >100k, handle NULLs, calculate avg by title
SELECT
  job_title_short,
  COUNT(*) as count,
  AVG(salary_year_avg) as avg_salary,
  MAX(job_posted_date) as latest_post
FROM job_postings_fact
WHERE job_work_from_home = true
  AND salary_year_avg > 100000
  AND salary_year_avg IS NOT NULL
  AND job_posted_date IS NOT NULL
GROUP BY job_title_short
ORDER BY avg_salary DESC;
```

## Notes

- **Type coercion silently fails in Python—test it in SQL first.** DuckDB's strict casting (`CAST(col AS INT)`) and `TRY_CAST()` reveal assumptions; catch these before pandas messes up your dtypes invisibly.
- **NULL handling is your biggest footgun.** `salary_year_avg > 100000` excludes NULLs by design; your pipeline logic must decide: drop, impute, or flag. Test both paths.
- **Schema validation belongs in tests, not documentation.** Use DuckDB to assert that incoming data has expected columns and types before transformation; fail fast with clear error messages.
- **Connects to: pytest fixtures + parametrize for testing multiple data scenarios, Pydantic models for type-safe contract definitions, and dbt tests (which also use SQL).**
- **Revisit: transaction semantics (DuckDB writes are atomic but single-threaded), memory limits on large datasets (use Arrow/Parquet I/O), and when to graduate from DuckDB to a real warehouse (when your test dataset > RAM or you need concurrent writes).**
