---
date: 2026-11-09
phase: python
topic: Numpy: vectorized operations and broadcasting rules
---

# Numpy: vectorized operations and broadcasting rules

*Python for data engineering*

## Concept

Vectorized operations in NumPy operate on entire arrays without explicit Python loops, delegating computation to optimized C code—typically 10–100× faster than iterating row-by-row. Broadcasting is the mechanism that allows operations between arrays of different shapes: a scalar broadcasts to match array dimensions, a 1D array broadcasts across missing dimensions, and dimensions of size 1 broadcast to match larger dimensions. In data pipelines, vectorization matters because you often transform millions of rows; a loop-based salary normalization or date calculation becomes a bottleneck, while `np.where()`, `np.clip()`, or `np.log1p()` finish instantly. Without understanding broadcasting rules, operations silently produce wrong shapes, misaligned data, or cryptic shape-mismatch errors that are hard to debug in production code.

## Practice

**Problem:** You have a job_postings fact table and need to flag outlier salaries (those beyond ±2 standard deviations from the mean) while handling missing values, then scale non-outliers to [0, 1] range per job_work_from_home category.

```sql
WITH salary_stats AS (
  SELECT
    job_work_from_home,
    AVG(salary_year_avg) AS mean_salary,
    STDDEV_POP(salary_year_avg) AS std_salary,
    COUNT(*) AS cnt
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
  GROUP BY job_work_from_home
),
flagged AS (
  SELECT
    j.job_id,
    j.salary_year_avg,
    j.job_work_from_home,
    CASE
      WHEN ABS(j.salary_year_avg - s.mean_salary) > 2 * s.std_salary THEN 1
      ELSE 0
    END AS is_outlier,
    j.salary_year_avg - s.mean_salary AS centered_salary,
    s.std_salary
  FROM job_postings_fact j
  LEFT JOIN salary_stats s ON j.job_work_from_home = s.job_work_from_home
  WHERE j.salary_year_avg IS NOT NULL
)
SELECT
  job_id,
  salary_year_avg,
  job_work_from_home,
  is_outlier,
  CASE
    WHEN is_outlier = 1 THEN NULL
    ELSE (centered_salary / (std_salary * 4.0)) + 0.5
  END AS scaled_salary_01
FROM flagged
WHERE scaled_salary_01 IS NULL OR (scaled_salary_01 >= 0 AND scaled_salary_01 <= 1);
```

*In NumPy:* `outlier_mask = np.abs(salaries - mean) > 2 * std` then `scaled = np.where(outlier_mask, np.nan, (salaries - mean) / (4 * std) + 0.5)` applies the same logic to a million rows in milliseconds via broadcasting without a loop.

## Notes

- **Shape mismatches are silent bugs:** `(100,) + (10, 1)` broadcasts to `(100, 10)` without error; always print shapes before combining arrays in production code.
- **NaN propagation:** NumPy operations with NaN produce NaN; use `np.nanmean()`, `np.nanstd()` and `np.where()` to handle missing values explicitly rather than hoping they disappear.
- **Type consistency in pipelines:** Broadcasting happens before type checking; cast data consistently (int vs. float) before vectorized ops to avoid silent integer truncation in salary calculations.
- **Related: vectorization in Pandas** (`df['col'].apply()` is slow; use `df['col'].str.extract()`, `.dt.year`, or `.clip()` instead) and Polars' expression API, which formalizes lazy vectorization.
- **Revisit:** axis parameter in reductions (`np.sum(axis=0)` vs `axis=1`) and advanced indexing (`arr[mask]`, fancy indexing) which are special cases of broadcasting.
