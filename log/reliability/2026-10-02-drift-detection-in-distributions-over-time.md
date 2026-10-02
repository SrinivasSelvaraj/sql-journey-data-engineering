---
date: 2026-10-02
phase: reliability
topic: Drift detection in distributions over time
---

# Drift detection in distributions over time

*Quality, reliability and the professional layer*

## Concept

Drift detection monitors whether the statistical properties of your data change unexpectedly over time. This includes schema drift (columns added/removed), value drift (distributions shift), and anomaly drift (sudden spikes in nulls or out-of-range values). Without it, your pipelines silently produce incorrect aggregations, your ML models degrade without warning, and stakeholders make decisions on stale patterns.

The moment you hand off a pipeline to production, you stop being a builder and start being an owner. That ownership means establishing guardrails. A salary column that averaged $95k last month but $65k this month signals either a data quality issue (job posting sites changed reporting standards) or a real market shift—but you won't know which without measurement.

Drift detection lives at the intersection of schema validation and statistical testing. You're not just checking "does the data exist?" but "does it behave like it should?" Implement it as checks that run *after* ingestion but *before* downstream consumption, flagging issues for investigation rather than letting them cascade.

## Practice

**Problem:** Your `job_postings_fact` salary data has begun showing unexpected patterns. Last quarter, `salary_year_avg` averaged $92,500 with a standard deviation of $28,000. This month, you notice the average dropped to $71,000. You need to detect whether this is genuine market drift or a data quality regression (e.g., more part-time roles being included, or a source system bug).

```sql
WITH monthly_stats AS (
  SELECT
    DATE_TRUNC('month', job_posted_date) AS month,
    COUNT(*) AS record_count,
    COUNT(CASE WHEN salary_year_avg IS NULL THEN 1 END) AS null_count,
    ROUND(AVG(salary_year_avg)::numeric, 2) AS avg_salary,
    ROUND(STDDEV_POP(salary_year_avg)::numeric, 2) AS stddev_salary,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary_year_avg)::numeric, 2) AS p25,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary_year_avg)::numeric, 2) AS p75
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '6 months'
  GROUP BY DATE_TRUNC('month', job_posted_date)
),
baseline AS (
  SELECT * FROM monthly_stats
  WHERE month = DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')
),
current AS (
  SELECT * FROM monthly_stats
  WHERE month = DATE_TRUNC('month', CURRENT_DATE)
)
SELECT
  current.month,
  current.record_count,
  current.null_count,
  ROUND(((current.null_count::float / current.record_count) * 100)::numeric, 2) AS null_pct,
  current.avg_salary,
  baseline.avg_salary AS baseline_avg,
  ROUND(((current.avg_salary - baseline.avg_salary) / baseline.avg_salary * 100)::numeric, 2) AS pct_change,
  CASE 
    WHEN ABS((current.avg_salary - baseline.avg_salary) / baseline.avg_salary) > 0.15 THEN 'ALERT: >15% drift'
    WHEN (current.null_count::float / current.record_count) > 0.05 THEN 'ALERT: >5% nulls'
    ELSE 'NORMAL'
  END AS drift_status
FROM current
LEFT JOIN baseline ON 1=1;
```

## Notes

- **Baseline choice matters:** Don't compare month-to-month if you have genuine seasonality (e.g., January hiring surges). Use year-over-year or a rolling median of the past 6 months as your reference.

- **Threshold tuning is domain work:** A 15% salary drift threshold might be reasonable in stable markets but too aggressive during recessions. Partner with stakeholders to set bounds; automated alerts without context breed alert fatigue.

- **Schema and value drift are separate problems:** Use `information_schema` queries to detect added/removed columns; use statistical checks like these for *value* drift. Both matter, but they need different remediation paths.

- **Connect to data contracts:** Drift detection is your enforcement mechanism for contracts you've written. If you promised downstream teams that `salary_year_avg` would never have >2% nulls, this check proves you kept it—or flags violations before they consume bad data.

- **Revisit: outlier detection, anomaly scoring, and alerting infrastructure.** Drift is often a symptom, not the root cause. You'll eventually want to dig into *why* it happened.
