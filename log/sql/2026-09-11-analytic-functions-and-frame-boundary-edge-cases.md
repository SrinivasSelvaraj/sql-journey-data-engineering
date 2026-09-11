---
date: 2026-09-11
phase: sql
topic: Analytic functions and frame boundary edge cases
---

# Analytic functions and frame boundary edge cases

*SQL for analytics and engineering*

## Concept

Analytic (window) functions compute aggregates *over a sliding or fixed subset of rows* without collapsing the result set. The **frame boundary**—defined by ROWS BETWEEN or RANGE BETWEEN clauses—determines which rows participate in each calculation. Without explicit frame specification, SQL defaults to RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW, which often produces unintuitive results when you expect a full partition aggregate or a trailing window.

Frame boundary edge cases arise when:
- **CURRENT ROW semantics differ between ROWS and RANGE**: ROWS BETWEEN … CURRENT ROW includes exactly one physical row; RANGE BETWEEN … CURRENT ROW includes all rows with the same sort key value (dangerous with ties).
- **Partition + frame interact**: a frame cannot exceed partition boundaries, so UNBOUNDED FOLLOWING may silently truncate.
- **NULL handling in ORDER BY**: rows with NULL sort keys may fall outside expected frames, or behave inconsistently across databases.

Getting frames wrong causes silent data errors: you'll sum only partial windows, compute wrong running totals, or mysteriously exclude tied rows from calculations.

## Practice

**Problem:** For each job posting, calculate (1) the cumulative count of postings in that salary bucket up to that date, and (2) the average salary of the *entire* salary bucket (not cumulative). Use `DENSE_RANK()` to identify salary buckets. Ensure the cumulative count does not jump when multiple postings share the same date.

```sql
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_posted_date,
  
  -- Salary bucket: group by 20k ranges
  DENSE_RANK() OVER (
    ORDER BY FLOOR(salary_year_avg / 20000) * 20000
  ) AS salary_bucket,
  
  -- Cumulative count within salary bucket, ordered by date
  -- ROWS ensures we count exactly one row per posting, even if dates match
  COUNT(*) OVER (
    PARTITION BY FLOOR(salary_year_avg / 20000) * 20000
    ORDER BY job_posted_date
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS cumulative_count_in_bucket,
  
  -- Avg salary of entire bucket: full partition, no frame
  AVG(salary_year_avg) OVER (
    PARTITION BY FLOOR(salary_year_avg / 20000) * 20000
  ) AS avg_salary_in_bucket
  
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
ORDER BY salary_year_avg, job_posted_date;
```

## Notes

- **Default frame trap**: `SUM(salary) OVER (PARTITION BY job_location ORDER BY job_posted_date)` defaults to RANGE CURRENT ROW, summing only rows matching that date—almost never what you want. Always specify ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW explicitly.
- **ROWS vs RANGE with ties**: ROWS treats each physical row as distinct; RANGE treats all rows with identical sort key as a peer group. When job_posted_date has duplicates, RANGE CURRENT ROW pulls in all same-day rows, ROWS CURRENT ROW pulls in only one.
- **Frame + NULL ordering**: NULL handling in ORDER BY varies (some DBs sort NULL first, others last). If NULL appears in your frame boundary, test behavior with `NULLS FIRST` / `NULLS LAST` explicitly.
- **Performance consideration**: Large UNBOUNDED frames (especially RANGE) can force sort-based computation. ROWS frames are often faster; consider materialized CTEs if frame logic becomes complex.
- **Connects to**: LAG/LEAD (which ignore frames), FIRST_VALUE/LAST_VALUE (frame-sensitive), and query plan analysis (watch for Sort → Window in EXPLAIN output as a performance red flag).
