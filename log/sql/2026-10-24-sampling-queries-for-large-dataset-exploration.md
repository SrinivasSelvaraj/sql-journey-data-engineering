---
date: 2026-10-24
phase: sql
topic: Sampling queries for large dataset exploration
---

# Sampling queries for large dataset exploration

*SQL for analytics and engineering*

## Concept

Sampling queries allow you to explore and validate data patterns on large datasets without materializing millions of rows—critical when you have billions of records and need fast feedback loops during analysis or debugging. Instead of `SELECT *` or even filtered aggregates, you extract a representative subset via `LIMIT`, `TABLESAMPLE`, or random row selection, trading statistical perfection for speed and resource efficiency.

This matters most during the exploratory phase: before writing expensive transformations, you want to inspect data quality, distribution, and edge cases on a small, queryable result set. Without sampling, you risk: runaway queries that lock tables, OOM errors in your analytics tool, and slow iteration cycles that kill productivity. It's also essential for testing query logic—write against 0.1% of data, validate correctness, then scale to 100%.

The tension is between bias and speed. `LIMIT 1000` is fastest but risks selecting only recent/clustered records. `TABLESAMPLE` (Postgres, Snowflake, BigQuery) reads random blocks, safer but less portable. Row-number hashing (`WHERE hash(id) % 100 = 0`) gives you ~1% deterministically, reproducible across runs.

## Practice

**Problem:** You're investigating salary trends in job postings but the table has 500M rows. Write a query that samples ~10K rows (2%) uniformly across job titles to inspect salary distributions without full table scan, ensuring the sample is repeatable.

```sql
SELECT 
  job_title_short,
  COUNT(*) as sample_count,
  ROUND(AVG(salary_year_avg), 0) as avg_salary,
  MIN(salary_year_avg) as min_salary,
  MAX(salary_year_avg) as max_salary
FROM job_postings_fact
WHERE ABS(CAST(HASH(job_id) AS INT64)) % 50 = 0  -- ~2% deterministic sample
  AND salary_year_avg IS NOT NULL
GROUP BY job_title_short
ORDER BY sample_count DESC;
```

**Alternative using TABLESAMPLE** (if on Snowflake/BigQuery):
```sql
SELECT 
  job_title_short,
  COUNT(*) as sample_count,
  ROUND(AVG(salary_year_avg), 0) as avg_salary
FROM job_postings_fact TABLESAMPLE (2 PERCENT)
WHERE salary_year_avg IS NOT NULL
GROUP BY job_title_short
ORDER BY sample_count DESC;
```

## Notes

- **Hash-based sampling is portable:** `WHERE ABS(HASH(id)) % N = 0` works across most SQL engines; adjust N to control percentage (N=50 → ~2%, N=100 → ~1%). Always use ABS to handle negative hash values.
- **TABLESAMPLE is faster but engine-specific:** Reads physical blocks randomly; faster than hashing but syntax differs (Postgres `TABLESAMPLE BERNOULLI`, Snowflake `TABLESAMPLE`, BigQuery same). Check your system's docs.
- **LIMIT is biased but acceptable for quick peeks:** Good for schema inspection and sanity checks, but introduces ordering bias if data is clustered (e.g., all recent jobs first). Never use alone for statistical analysis.
- **Stratified sampling matters:** If you care about distribution across categories, use `ROW_NUMBER() OVER (PARTITION BY job_title_short ORDER BY RANDOM()) <= 100` per group to sample evenly from each title—prevents one-heavy category from dominating.
- **Always validate sample size against question:** A 2% sample might give you 10K rows but also high variance in tail categories; confirm your sample is large enough for the insight you need, then scale query complexity gradually.
