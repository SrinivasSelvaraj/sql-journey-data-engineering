---
date: 2026-11-07
phase: sql
topic: Pivot and unpivot: wide-to-tall and tall-to-wide transforms
---

# Pivot and unpivot: wide-to-tall and tall-to-wide transforms

*SQL for analytics and engineering*

## Concept

**Pivot** transforms tall data (many rows, few columns) into wide data (few rows, many columns) by rotating a dimension into column headers. **Unpivot** does the reverse—converting wide data into tall format. These transforms are essential for analytics because different consumers expect different shapes: dashboards often need wide pivots for cross-tabulation, while data pipelines and ML require tall normalized forms.

The distinction matters because storage, query performance, and tool compatibility depend on shape. A tall table with job location as a row value is efficient for filtering and aggregation; a wide table with each location as a column is convenient for side-by-side comparison but becomes unwieldy with many dimensions (the "curse of wide tables"). Without pivot/unpivot operations, you either duplicate logic across reports or force inefficient client-side reshaping.

When pivoting, you must decide: what becomes rows (GROUP BY dimension), what becomes columns (PIVOT dimension), and what aggregation fills cells (usually SUM, COUNT, AVG). Mistakes happen when the PIVOT dimension has nulls or when you forget that the output loses granularity—pivoting always aggregates.

## Practice

**Problem:** Create a cross-tabulation showing the average salary by job title (rows) and whether the role is remote-eligible (columns: "Remote" vs "On-Site").

```sql
SELECT 
  job_title_short,
  ROUND(AVG(CASE WHEN job_work_from_home THEN salary_year_avg END), 0) AS remote_avg_salary,
  ROUND(AVG(CASE WHEN NOT job_work_from_home THEN salary_year_avg END), 0) AS onsite_avg_salary
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY job_title_short
ORDER BY remote_avg_salary DESC NULLS LAST;
```

*(Alternative using FILTER clause in PostgreSQL/BigQuery:)*
```sql
SELECT 
  job_title_short,
  ROUND(AVG(salary_year_avg) FILTER (WHERE job_work_from_home), 0) AS remote_avg_salary,
  ROUND(AVG(salary_year_avg) FILTER (WHERE NOT job_work_from_home), 0) AS onsite_avg_salary
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY job_title_short
ORDER BY remote_avg_salary DESC NULLS LAST;
```

## Notes

- **NULL handling in pivots:** CASE expressions return NULL when the condition is false; aggregates (AVG, SUM) skip NULLs. This is usually desired but can silently hide missing data—always validate counts alongside aggregates.

- **Dialect variation:** Standard SQL uses CASE WHEN; some platforms (SQL Server, Oracle) have native PIVOT syntax that's terser but less portable. FILTER (PostgreSQL, BigQuery, SQLite 3.30+) is cleaner than nested CASE but not universal.

- **Unpivoting (tall-to-wide reversal):** Use UNION ALL to stack multiple CASE branches or UNPIVOT keyword (SQL Server, Oracle, modern SQLite). Example: `SELECT job_title_short, 'remote' AS work_mode, remote_avg_salary AS salary FROM pivoted_table UNION ALL SELECT job_title_short, 'onsite', onsite_avg_salary FROM pivoted_table`.

- **Performance trap:** Pivoting high-cardinality dimensions (e.g., 1000 unique locations → 1000 columns) creates wide sparse tables and poor query plans. Know your dimension size before pivoting; consider keeping tall for storage and pivoting only at query/report layer.

- **Adjacent topics:** Star schema design (fact/dimension tables naturally tall); denormalization trade-offs; window functions (ROW_NUMBER, RANK for rank-based pivots); materialized views for pre-pivoted analytics tables.
