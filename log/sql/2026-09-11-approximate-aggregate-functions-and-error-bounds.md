---
date: 2026-09-11
phase: sql
topic: Approximate aggregate functions and error bounds
---

# Approximate aggregate functions and error bounds

*SQL for analytics and engineering*

## Concept

Approximate aggregate functions trade precision for speed and memory efficiency when computing over massive datasets. Instead of scanning and materializing every row (exact aggregation), approximate functions use probabilistic data structures—like HyperLogLog for distinct counts, t-digest for quantiles, or reservoir sampling for sampling—to return results within a specified error bound, typically in a single or two passes. They're essential in analytical databases (Redshift, BigQuery, Snowflake) when you're querying billions of rows and a 0.5% error on a COUNT(DISTINCT) is acceptable, but waiting 60 seconds for an exact answer is not.

Without approximate functions, you either accept long query times or you pre-aggregate and cache results, both of which create operational burden. The error bound is usually expressed as a relative percentage (e.g., ±2% for HyperLogLog) and is guaranteed probabilistically, not deterministically. You must understand when approximation is safe—interactive dashboards, user-facing analytics, capacity planning—versus when exactness is mandatory—financial reconciliation, compliance reporting, fraud detection.

## Practice

**Problem:** A recruiter dashboard needs to show the approximate count of distinct job titles posted in the last 90 days across all locations, and an approximate 95th percentile salary, refreshed every 5 minutes. The job_postings_fact table has 500M rows. An exact query takes 45 seconds; the dashboard needs sub-2-second response.

```sql
SELECT
  APPROX_COUNT_DISTINCT(job_title_short) AS approx_distinct_titles,
  APPROX_PERCENTILE_CONT(salary_year_avg, 0.95) AS approx_95th_percentile_salary,
  COUNT(*) AS total_postings
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
  AND salary_year_avg IS NOT NULL;
```

**Why this works:** `APPROX_COUNT_DISTINCT` uses HyperLogLog internally, returning a count within ~2% error in near-constant memory. `APPROX_PERCENTILE_CONT` uses t-digest or similar to sketch the salary distribution without materializing all 500M values. The query completes in <500ms. For a financial reconciliation query, you'd use `COUNT(DISTINCT job_title_short)` and `PERCENTILE_CONT(...)` instead, accepting the 45-second latency.

## Notes

- **Approximate functions vary by database:** Postgres has no built-in approx functions (use extensions or pre-aggregation); Redshift, BigQuery, and Snowflake all have them, but with different names and error guarantees. Always check your vendor's documentation.
- **Error bounds are probabilistic, not worst-case:** HyperLogLog gives you a *standard error* of ~1.04/√m where m is the number of registers; you're not guaranteed ±X%, you're guaranteed that with high probability the error falls in a range. For critical decisions, validate against a small exact sample.
- **Approximate functions don't work well on small datasets:** If your result set is <10k rows, approximation overhead (sketch initialization, serialization) often makes the query slower than exact computation. Use approximation at scale.
- **Combine with `GROUP BY` carefully:** Some databases allow `APPROX_COUNT_DISTINCT(...) OVER (PARTITION BY ...)` but not all; pushing approximation into subqueries or CTEs is often safer and forces you to think about cardinality per group.
- **Adjacent topics:** histogram sketches (for distribution visualization), streaming aggregates (windowed approximate counts in real-time systems), and data sampling strategies (when approximation isn't available, draw a random sample and extrapolate).
