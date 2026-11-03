---
date: 2026-11-03
phase: reliability
topic: Data profiling: distribution and pattern discovery
---

# Data profiling: distribution and pattern discovery

*Quality, reliability and the professional layer*

## Concept

Data profiling is the systematic examination of actual data values, distributions, and patterns to establish what "normal" looks like—and more importantly, what deviation signals a problem. It answers: Are salaries lognormally distributed or bimodal? Do 95% of records cluster in one location? Is there temporal drift in posting frequency? Without this foundation, you're flying blind. You catch typos and duplicates with basic validation; profiling catches silent degradation: a vendor switching data format, upstream logic changing, or a segment disappearing entirely.

The professional layer depends on it because it transforms you from reactive (fixing broken records after complaints) to proactive (detecting shifts before they corrupt downstream models). Data quality rules without profiling are guesses. Rules informed by profiling are defensible, versioned, and traceable—they document what you *know* about your source, not what you assume.

## Practice

**Problem:** Your job_postings_fact table is used by the hiring analytics team. Last month, salary and location distributions looked stable. This month, a report flagged anomalies but nobody knows if it's real signal or ingestion noise. You need to establish baseline profiles and detect drift without manual inspection.

```sql
-- Establish baseline profile for one reporting period
WITH profile_metrics AS (
  SELECT
    DATE_TRUNC('month', job_posted_date) AS month,
    COUNT(*) AS record_count,
    COUNT(DISTINCT job_location) AS unique_locations,
    COUNT(CASE WHEN salary_year_avg IS NULL THEN 1 END) AS null_salary_count,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary_year_avg) AS salary_q1,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY salary_year_avg) AS salary_median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary_year_avg) AS salary_q3,
    ROUND(100.0 * COUNT(CASE WHEN job_work_from_home THEN 1 END) / COUNT(*), 2) AS pct_remote,
    COUNT(CASE WHEN job_title_short IN ('Data Engineer', 'Data Analyst') THEN 1 END) AS data_roles_count
  FROM job_postings_fact
  GROUP BY DATE_TRUNC('month', job_posted_date)
)
SELECT
  month,
  record_count,
  unique_locations,
  null_salary_count,
  ROUND(salary_q1::NUMERIC, 0) AS salary_q1,
  ROUND(salary_median::NUMERIC, 0) AS salary_median,
  ROUND(salary_q3::NUMERIC, 0) AS salary_q3,
  salary_q3 - salary_q1 AS iqr,
  pct_remote,
  data_roles_count
FROM profile_metrics
ORDER BY month DESC;
```

This gives you quantiles, null rates, and composition metrics. Store these results in a `data_profile_history` table; compare month-to-month and flag rows where IQR shifts >15% or remote percentage swings >10 points.

## Notes

- **Confusing profiling with validation:** Profiling *discovers* rules; validation *enforces* them. You profile first to set thresholds, then codify those thresholds as pipeline tests. Doing it backwards means your rules are arbitrary.
- **Forgetting temporal dimension:** Distributions drift seasonally or due to upstream changes. Profile by cohort (date posted, source, region) not just globally, or you'll miss real problems hiding in aggregates.
- **Connects to:** outlier detection (profiling identifies what's extreme), schema evolution (distributions change when fields are retyped), and SLA monitoring (you can't define acceptable latency or completeness without knowing baseline behavior).
- **Common mistake:** Running one profile snapshot and calling it ground truth. Profile over 3–6 months to capture seasonality and normal variance, then use control limits (e.g., ±2 SD) for drift detection.
- **Revisit:** Statistical tests (Kolmogorov-Smirnov, chi-square) for formalizing drift detection; great tools like Great Expectations or Soda automate profiling and alerting, but understanding the *why* behind the numbers matters more than the tool.
