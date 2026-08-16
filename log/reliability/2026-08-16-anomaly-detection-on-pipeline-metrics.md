---
date: 2026-08-16
phase: reliability
topic: Anomaly detection on pipeline metrics
---

# Anomaly detection on pipeline metrics

*Quality, reliability and the professional layer*

## Concept

Anomaly detection on pipeline metrics means establishing normal operating ranges for data quality and performance indicators, then alerting when observed values deviate significantly. This is about knowing whether your pipeline is working—not just whether it ran without errors. A job posting ingestion pipeline might normally load 500–800 records daily; if today it loaded 50, that's a silent failure that batch completion masks entirely.

Without anomaly detection, you discover problems reactively: a stakeholder complains that numbers look wrong, or you notice during a manual spot-check that a column is unexpectedly NULL. By then, corrupted data has already propagated downstream into analytics and decision-making. The difference between building pipelines and owning them is the willingness to spend engineering time automating detection rather than relying on human vigilance.

Detection works best when you establish baselines for record counts, null percentages, min/max values, and freshness metrics—then set thresholds that trigger alerts when metrics fall outside expected bounds. This requires you to understand your data's natural variability (seasonal hiring dips, weekend lulls) rather than using static limits.

## Practice

**Problem:** Your `job_postings_fact` table ingest runs nightly. You need to detect when:
- Fewer than 100 records load (something broke upstream)
- More than 50% of `salary_year_avg` values are NULL (schema change or parsing failure)
- The latest `job_posted_date` is older than 2 days (staleness)

```sql
WITH metrics AS (
  SELECT
    CURRENT_DATE as check_date,
    COUNT(*) as record_count,
    COUNTIF(salary_year_avg IS NULL) / COUNT(*) as null_salary_pct,
    MAX(job_posted_date) as latest_post_date,
    CURRENT_DATE - MAX(job_posted_date) as days_stale
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - 7
)
SELECT
  check_date,
  record_count,
  CASE 
    WHEN record_count < 100 THEN 'ALERT: Low record count'
    WHEN null_salary_pct > 0.5 THEN 'ALERT: High null salary rate'
    WHEN days_stale > 2 THEN 'ALERT: Data staleness exceeded'
    ELSE 'OK'
  END as status,
  null_salary_pct,
  latest_post_date
FROM metrics;
```

Store results in a `pipeline_health_checks` audit table and trigger alerts (email, Slack, PagerDuty) when status != 'OK'.

## Notes

- **Baseline drift:** Your "normal range" changes over time. Set thresholds generously at first, then tighten them after 2–4 weeks of stable operation.
- **Alerting fatigue:** Too many false positives destroy trust in alerts. Start with the 2–3 metrics that would cause the most damage if wrong, not all possible checks.
- **Connected to:** Data lineage (knowing which downstream tables depend on this one), SLO/SLA definitions (what does "acceptable" mean for your business?), and test-driven data engineering.
- **Common mistake:** Running checks *after* data loads into production tables. Run them on staging or as part of the load logic so you can reject bad data before it propagates.
- **Revisit:** Seasonal patterns, threshold tuning based on alert history, and correlation between metrics (e.g., low record count + high nulls suggests parsing failure, not volume drop).
