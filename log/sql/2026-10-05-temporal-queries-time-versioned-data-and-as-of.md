---
date: 2026-10-05
phase: sql
topic: Temporal queries: time-versioned data and AS OF
---

# Temporal queries: time-versioned data and AS OF

*SQL for analytics and engineering*

## Concept

Temporal queries retrieve data as it existed at a specific point in time, essential when a table tracks historical changes through versioning columns (like `valid_from`, `valid_to`, `dbt_valid_from`, `dbt_valid_to`) or when you need to reconstruct state at a past date. The `AS OF` syntax (supported in some databases like Snowflake, BigQuery, and PostgreSQL 15+) queries a table's state at a specific timestamp without manually filtering date ranges—it's declarative and often optimized by the engine.

Without temporal awareness, you'll either miss historical context (querying only current data when you need last month's salaries) or incorrectly double-count records during overlapping validity periods. This matters in analytics for year-over-year comparisons, in auditing to prove what data was used for a decision, and in warehousing to avoid late-arriving facts corrupting historical snapshots.

Many teams implement versioning through slowly changing dimensions (SCD Type 2) or dbt snapshots, storing `dbt_valid_from` and `dbt_valid_to` columns. Querying these correctly requires filtering the valid range or using `AS OF` syntax if available; failing to do so introduces duplicates or stale values.

## Practice

**Problem:** You need to compare job posting salary trends. Report the average salary for "Data Analyst" roles posted as they existed on 2024-01-15 *and* on 2024-06-15 (to see if salaries shifted). Assume `job_postings_fact` has `dbt_valid_from` and `dbt_valid_to` columns tracking versioned job title changes.

```sql
WITH analyst_jan AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    dbt_valid_from,
    dbt_valid_to
  FROM job_postings_fact
  WHERE job_title_short = 'Data Analyst'
    AND dbt_valid_from <= '2024-01-15'
    AND (dbt_valid_to > '2024-01-15' OR dbt_valid_to IS NULL)
),
analyst_jun AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    dbt_valid_from,
    dbt_valid_to
  FROM job_postings_fact
  WHERE job_title_short = 'Data Analyst'
    AND dbt_valid_from <= '2024-06-15'
    AND (dbt_valid_to > '2024-06-15' OR dbt_valid_to IS NULL)
)
SELECT 
  'Jan 2024' AS period,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary
FROM analyst_jan
UNION ALL
SELECT 
  'Jun 2024' AS period,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary
FROM analyst_jun;
```

## Notes

- **Null handling:** Always check if `valid_to` is `NULL` or uses a sentinel date like `9999-12-31` to represent "still current"—mixing them breaks temporal logic.
- **AS OF syntax:** If your database supports it (Snowflake's `AT(TIMESTAMP => '...')`, BigQuery's `FOR SYSTEM_TIME AS OF`), use it instead of manual filtering; it's clearer and often faster.
- **SCD Type 2 vs. temporal tables:** Manually versioned tables with date columns are common in dbt; native temporal tables (PostgreSQL, SQL Server) manage versioning automatically but require different query patterns.
- **Overlapping validity periods:** If two versions of the same record overlap, you have a data quality bug or intentional retroactive correction—investigate first; never silently pick the newest one.
- **Performance:** Temporal queries on wide tables benefit from clustering on `valid_from`/`valid_to` and indexes; materialized historical snapshots (e.g., daily snapshots) are often cheaper than computing versions on-the-fly for large fact tables.
