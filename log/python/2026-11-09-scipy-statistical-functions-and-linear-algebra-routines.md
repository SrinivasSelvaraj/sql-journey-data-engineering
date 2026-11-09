---
date: 2026-11-09
phase: python
topic: Scipy: statistical functions and linear algebra routines
---

# Scipy: statistical functions and linear algebra routines

*Python for data engineering*

## Concept

SciPy provides production-grade statistical functions and linear algebra routines built on NumPy—essential when your pipeline needs to compute correlations, perform hypothesis testing, solve systems of equations, or detect anomalies in data flows. Unlike quick pandas `.corr()` calls, SciPy's `scipy.stats` and `scipy.linalg` modules offer control over method selection, numerical stability, and error handling, which matters when processing financial data, sensor streams, or any high-stakes aggregation where precision and reproducibility are non-negotiable.

Without robust statistical tooling, pipelines silently produce wrong answers: correlation functions that fail on NaN inputs, matrix inversions that overflow, p-values computed with unstable algorithms. SciPy survives these edge cases by offering explicit parameters—`nan_policy`, `rcond`, dtype promotion—and returns both result *and* diagnostics (standard error, condition numbers). This transparency is what makes tests pass and operators sleep at night.

The key advantage in data engineering: SciPy operations are vectorized and directly consumable in ETL—you can compute regression residuals, test distribution goodness-of-fit, or solve least-squares problems without loops, and do it consistently across dev, test, and production environments.

## Practice

**Problem:** You need to flag suspicious salary outliers in job postings per job title, but only when you have enough data confidence. Compute z-scores for `salary_year_avg` grouped by `job_title_short`, then flag records where |z-score| > 2.5, but only for groups with ≥ 30 samples (to avoid spurious flags on small cohorts).

```sql
WITH salary_stats AS (
  SELECT
    job_title_short,
    COUNT(*) as group_count,
    AVG(salary_year_avg) as mean_salary,
    STDDEV_POP(salary_year_avg) as stddev_salary
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
    AND job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY
  GROUP BY job_title_short
  HAVING COUNT(*) >= 30
)
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  ABS((salary_year_avg - stats.mean_salary) / NULLIF(stats.stddev_salary, 0)) as z_score,
  CASE
    WHEN ABS((salary_year_avg - stats.mean_salary) / NULLIF(stats.stddev_salary, 0)) > 2.5
    THEN 'OUTLIER'
    ELSE 'NORMAL'
  END as flag
FROM job_postings_fact jpf
INNER JOIN salary_stats stats ON jpf.job_title_short = stats.job_title_short
WHERE jpf.salary_year_avg IS NOT NULL
  AND jpf.job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY
ORDER BY z_score DESC;
```

*(In Python: use `scipy.stats.zscore(group_salaries, nan_policy='omit')` with validation that group size ≥ 30 before calling.)*

## Notes

- **NaN handling is explicit:** `scipy.stats` functions accept `nan_policy` ('propagate', 'raise', 'omit')—never assume silent cleanup; test all three paths in unit tests.
- **Numerical stability over speed:** `scipy.linalg.solve()` is slower than naive matrix inversion but uses LU decomposition; always prefer it for ill-conditioned systems (condition number > 10¹⁰).
- **Type annotations matter here:** Return types from `scipy.stats.linregress()` changed in v1.7+; pin versions and use `@dataclass` or `TypedDict` to document output shape across your org.
- **Adjacent topics:** Connects to hypothesis testing (A/B test significance), anomaly detection pipelines, and `numpy.testing` for deterministic CI—all depend on reproducible random seeds and input validation.
- **Revisit:** The difference between population vs. sample statistics (`STDDEV_POP` vs `STDDEV_SAMP`); SciPy defaults to sample (N-1 denominator); mismatch here is a silent source of pipeline bugs.
