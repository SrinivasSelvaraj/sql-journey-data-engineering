---
date: 2026-09-30
phase: reliability
topic: Alerting: thresholds, anomalies and stakeholder routing
---

# Alerting: thresholds, anomalies and stakeholder routing

*Quality, reliability and the professional layer*

## Concept

Alerting transforms a passive data pipeline into an active, trustworthy system by notifying the right people when something breaks or deviates from expected behavior. Without alerting, data quality issues, pipeline failures, and anomalies sit silently in logs until someone manually discovers them—often after downstream stakeholders have already made decisions on stale or corrupted data.

Threshold-based alerts are the foundation: you define hard boundaries (e.g., "fail if zero rows loaded today") and trigger notifications when those conditions breach. Anomaly detection goes deeper, using statistical baselines or machine learning to flag unexpected patterns even when raw values appear normal (e.g., salary data suddenly 30% lower than historical average, or job postings spiking at 3 AM when they're always posted at 9 AM). Stakeholder routing ensures alerts reach the right person—a data engineer owns pipeline failures, a business analyst owns data anomalies, leadership owns SLA violations—so action happens fast and alert fatigue doesn't paralyze response.

Owning a pipeline means accepting accountability for both its correctness and its reliability. Without alerting, you are not owning it; you are simply building it and hoping. Alerting is the difference between "the pipeline ran" and "the pipeline ran *correctly* and someone verified it."

## Practice

**Problem:** The job_postings_fact table should load daily with roughly 500–800 new rows. Last week, a data source API silently started returning empty responses on weekends, but the pipeline "succeeded" with zero rows inserted. Analysts didn't notice for three days and published a report claiming job postings dropped 100% on Saturdays. Define alerts to catch this.

```sql
-- Threshold alert: fail if daily load is below minimum expected volume
SELECT 
  CURRENT_DATE AS alert_date,
  COUNT(*) AS rows_loaded,
  CASE 
    WHEN COUNT(*) < 500 THEN 'CRITICAL: Below minimum threshold (500 rows)'
    ELSE 'OK'
  END AS alert_status,
  'data_engineering' AS route_to
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE
HAVING COUNT(*) < 500;

-- Anomaly alert: flag when daily average salary deviates >2 std dev from rolling 30-day baseline
WITH salary_stats AS (
  SELECT 
    CURRENT_DATE AS check_date,
    AVG(salary_year_avg) AS today_avg_salary,
    (SELECT AVG(salary_year_avg) FROM job_postings_fact 
     WHERE job_posted_date BETWEEN CURRENT_DATE - 30 AND CURRENT_DATE - 1) AS baseline_avg,
    (SELECT STDDEV(salary_year_avg) FROM job_postings_fact 
     WHERE job_posted_date BETWEEN CURRENT_DATE - 30 AND CURRENT_DATE - 1) AS baseline_stddev
  FROM job_postings_fact
  WHERE job_posted_date = CURRENT_DATE
)
SELECT 
  check_date,
  today_avg_salary,
  baseline_avg,
  ABS(today_avg_salary - baseline_avg) / NULLIF(baseline_stddev, 0) AS stddev_distance,
  CASE 
    WHEN ABS(today_avg_salary - baseline_avg) / NULLIF(baseline_stddev, 0) > 2 
      THEN 'WARNING: Salary anomaly detected (2+ std dev from baseline)'
    ELSE 'OK'
  END AS alert_status,
  'business_analytics' AS route_to
FROM salary_stats
WHERE ABS(today_avg_salary - baseline_avg) / NULLIF(baseline_stddev, 0) > 2;
```

## Notes

- **Alert fatigue kills response.** If your system fires 50 alerts daily and 48 are noise, the team stops reading them. Start with high-confidence thresholds and tune down only after you've built trust.
- **Alerting connects directly to observability.** Thresholds are useless without logs, metrics, and trace data showing *why* something failed—instrument your pipeline to log row counts, API response times, and data quality checks at each stage.
- **Routing is a sociotechnical problem.** The best alert means nothing if it goes to Slack channel nobody reads or emails buried in spam. Define escalation paths: warn data engineer first, then escalate to manager if unacknowledged after 1 hour.
- **Anomalies require baselines.** Don't run anomaly detection on day 1. Collect 2–4 weeks of clean historical data first so your baseline isn't poisoned by the very problems you're trying to detect.
- **Revisit thresholds seasonally.** Job postings may legitimately drop 20% in December or spike in September. Hard thresholds need business context—partner with stakeholders to define "expected normal" ranges by season, geography, or job category.
