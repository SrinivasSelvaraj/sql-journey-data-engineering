---
date: 2026-08-07
phase: sql
topic: Cohort retention tables
---

# Cohort retention tables

*SQL for analytics and engineering*

## Concept

A cohort retention table tracks how a group of users, customers, or entities defined by a shared characteristic (typically signup/join date) behaves over subsequent time periods. Instead of a single retention percentage, you create a matrix where rows represent cohorts and columns represent time periods elapsed since cohort formation, showing what fraction or count of the original cohort remained active or engaged.

Retention tables matter in analytics because they reveal cohort quality and product stickiness independent of total user growth. A company adding 1000 new users monthly looks healthy until you see that week-1 retention dropped from 40% to 15%—that's a signal no dashboard of raw counts captures. They're essential for unit economics, forecasting churn, and detecting when product changes broke engagement.

Without proper cohort tracking, you conflate growth trends with engagement trends. A spike in total active users might hide the fact that older cohorts are churning faster. You also lose the ability to A/B test cohort quality by signup source, campaign, or feature release date—critical for post-mortems on what killed engagement.

## Practice

**Problem:** For each month when jobs were posted, calculate the fraction of jobs from that cohort that remained "active" (had at least one posting) in each subsequent month, up to 6 months out. A job is considered part of a cohort by its job_posted_date month. Show cohort month, months-since-cohort (0–6), and retention rate rounded to 2 decimals.

```sql
WITH cohorts AS (
  SELECT 
    DATE_TRUNC('month', job_posted_date)::DATE AS cohort_month,
    job_id
  FROM job_postings_fact
),
cohort_sizes AS (
  SELECT 
    cohort_month,
    COUNT(DISTINCT job_id) AS cohort_size
  FROM cohorts
  GROUP BY cohort_month
),
job_months AS (
  SELECT 
    DATE_TRUNC('month', job_posted_date)::DATE AS activity_month,
    job_id
  FROM job_postings_fact
  GROUP BY DATE_TRUNC('month', job_posted_date), job_id
),
cohort_activity AS (
  SELECT 
    c.cohort_month,
    jm.activity_month,
    COUNT(DISTINCT jm.job_id) AS active_jobs
  FROM cohorts c
  INNER JOIN job_months jm ON c.job_id = jm.job_id
  GROUP BY c.cohort_month, jm.activity_month
)
SELECT 
  ca.cohort_month,
  (DATE_PART('month', ca.activity_month) - DATE_PART('month', ca.cohort_month) +
   12 * (DATE_PART('year', ca.activity_month) - DATE_PART('year', ca.cohort_month)))::INT AS months_since_cohort,
  ROUND(100.0 * ca.active_jobs / cs.cohort_size, 2) AS retention_rate_pct
FROM cohort_activity ca
INNER JOIN cohort_sizes cs ON ca.cohort_month = cs.cohort_month
WHERE (DATE_PART('month', ca.activity_month) - DATE_PART('month', ca.cohort_month) +
       12 * (DATE_PART('year', ca.activity_month) - DATE_PART('year', ca.cohort_month)))::INT BETWEEN 0 AND 6
ORDER BY ca.cohort_month, months_since_cohort;
```

## Notes

- **Month arithmetic trap:** Date difference calculations are error-prone across year boundaries; use `DATE_PART` with year adjustment or generate explicit month sequences to avoid off-by-one errors and gaps.
- **Denominator definition:** Cohort size must be defined *once* at cohort formation time, not recalculated dynamically—otherwise cohort members who churn influence both numerator and denominator inconsistently.
- **Activity vs. presence:** Distinguish whether "active" means *any* event, minimum threshold (e.g., ≥2 postings), or membership in good standing; this changes retention interpretation dramatically and should be encoded in CTE naming.
- **Sparse matrix handling:** Real retention tables often pivot to wide format (months as columns) for visualization; use `PIVOT` or conditional aggregation (`SUM(CASE WHEN months_since_cohort = 0 THEN retention_rate ELSE NULL END)`), but compute long-form first for correctness.
- **Adjacent concepts:** Connects to funnel analysis (cohorts at different conversion stages), lifetime value decomposition (cohort quality signals future revenue), and time-series anomaly detection (identifying cohorts that underperform trend).
