---
date: 2026-10-04
phase: sql
topic: SQL dialect differences: migrating between databases
---

# SQL dialect differences: migrating between databases

*SQL for analytics and engineering*

## Concept

SQL dialects vary across database systems (PostgreSQL, MySQL, SQL Server, BigQuery, Snowflake) in syntax, functions, and data types. Functions like `DATEDIFF()`, `SUBSTRING()`, and `CONCAT()` have different signatures or don't exist in certain systems. String handling, NULL behavior, window function syntax, and type casting differ subtly but critically—a query that runs perfectly in PostgreSQL may fail or produce wrong results in BigQuery. Understanding these differences prevents silent bugs during migration and helps you write portable code or know exactly what needs refactoring when switching systems.

Data type availability matters too: PostgreSQL has `INTERVAL` and `JSONB`, while BigQuery uses `TIMESTAMP` with different precision. Date arithmetic syntax changes—MySQL uses `DATE_ADD(col, INTERVAL 1 DAY)` while PostgreSQL uses `col + INTERVAL '1 day'`. Window functions and aggregate behavior (e.g., `GROUP BY` strictness, implicit ordering) also vary. Learning to recognize dialect-specific patterns early saves hours of debugging in production migrations.

## Practice

**Problem:** Write a query that calculates the average salary for remote jobs posted in the last 90 days, grouped by job title. The query must work in both PostgreSQL and BigQuery without modification.

```sql
SELECT 
  job_title_short,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary,
  COUNT(*) AS job_count
FROM job_postings_fact
WHERE 
  job_work_from_home = TRUE
  AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY job_title_short
HAVING COUNT(*) >= 2
ORDER BY avg_salary DESC;
```

*Notes on portability:* `CURRENT_DATE` and basic `INTERVAL` syntax work in both PostgreSQL and BigQuery. For MySQL, replace `INTERVAL '90 days'` with `INTERVAL 90 DAY`. For SQL Server, use `DATEADD(DAY, -90, CAST(GETDATE() AS DATE))`. Always test date arithmetic and aggregate functions in your target dialect.

## Notes

- **Silent type coercion failures**: PostgreSQL is strict about type casting; SQL Server is permissive. A `salary_year_avg` compared to a string may fail in one system and auto-cast in another. Explicit `CAST()` is safer than relying on implicit conversion.
- **NULL handling inconsistency**: `COUNT(*)` vs. `COUNT(column)` behaves the same across systems, but `SUM()` with NULLs and `COALESCE()` function availability differ. Always check how your system treats NULL in aggregates.
- **String functions are chaos**: `SUBSTRING()` in PostgreSQL uses 1-based indexing; some systems use 0-based. `CONCAT()` doesn't exist in all dialects—use `||` (PostgreSQL/SQL Server) or `CONCAT_WS()` (MySQL/BigQuery) instead.
- **Window function framing**: `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` is standard, but implicit ordering and default frames differ. BigQuery requires explicit `ORDER BY` in window functions; PostgreSQL is more flexible.
- **Revisit**: Query plan analysis (EXPLAIN), indexing strategies per dialect, and when to use vendor-specific optimizations (e.g., Snowflake clustering, BigQuery partitioning) over portable code.
