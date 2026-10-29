---
date: 2026-10-29
phase: pipelines
topic: Pipeline monitoring dashboards and alerting
---

# Pipeline monitoring dashboards and alerting

*Pipelines and orchestration*

## Concept

A pipeline monitoring dashboard surfaces the health, performance, and correctness of data jobs in real time. It answers: *Is this pipeline running? How long did it take? Did it fail, and if so, why?* Without dashboards, failures hide in logs or get discovered only when downstream consumers complain. Alerting amplifies this—it notifies you *before* stale data breaks reports or triggers false business decisions.

Effective monitoring requires three layers: **execution metrics** (task duration, retry counts, success/failure rates), **data quality metrics** (row counts, null rates, schema violations), and **business metrics** (freshness lag, completeness, duplicate detection). A job may complete successfully yet load corrupt data; a dashboard catches both the symptom (slow query) and the root cause (unexpected null spike in a key column).

Without this, pipelines become invisible. You ship data nobody can trust, teams blame "the data pipeline" generically, and incidents cascade because you only learn about problems hours or days late. The cost of a single undetected data quality issue often exceeds the cost of building robust monitoring.

## Practice

**Problem:** Your `job_postings_fact` table is updated daily at 2 AM UTC. You need to detect:
1. If the job hasn't loaded for 24+ hours (freshness failure)
2. If today's load has fewer rows than the 7-day average (anomaly)
3. If salary_year_avg contains unexpected nulls (data quality)

Create a monitoring query that flags these and logs results to an audit table:

```sql
WITH latest_load AS (
  SELECT 
    MAX(job_posted_date) AS last_load_date,
    COUNT(*) AS row_count_today
  FROM job_postings_fact
  WHERE job_posted_date = CURRENT_DATE
),
baseline AS (
  SELECT 
    AVG(daily_count) AS avg_7day_count,
    STDDEV(daily_count) AS stddev_7day
  FROM (
    SELECT 
      job_posted_date,
      COUNT(*) AS daily_count
    FROM job_postings_fact
    WHERE job_posted_date BETWEEN CURRENT_DATE - 7 AND CURRENT_DATE - 1
    GROUP BY job_posted_date
  ) t
)
INSERT INTO pipeline_monitoring_log (check_timestamp, check_name, status, detail)
SELECT 
  CURRENT_TIMESTAMP,
  check_name,
  CASE WHEN is_alert THEN 'ALERT' ELSE 'OK' END,
  detail
FROM (
  SELECT 'freshness' AS check_name, CURRENT_TIMESTAMP - last_load_date > INTERVAL '24 hours' AS is_alert,
    CONCAT('Last load: ', last_load_date) AS detail
  FROM latest_load
  UNION ALL
  SELECT 'row_count_anomaly', 
    row_count_today < (avg_7day_count - 2 * stddev_7day),
    CONCAT('Today: ', row_count_today, ' rows vs 7d avg: ', ROUND(avg_7day_count, 0))
  FROM latest_load, baseline
  UNION ALL
  SELECT 'null_salary_check',
    (SELECT COUNT(*) FROM job_postings_fact WHERE job_posted_date = CURRENT_DATE AND salary_year_avg IS NULL)
      > (SELECT COUNT(*) FROM job_postings_fact WHERE job_posted_date = CURRENT_DATE) * 0.05,
    CONCAT('Nulls in salary_year_avg: ',
      ROUND(100 * (SELECT COUNT(*) FROM job_postings_fact WHERE job_posted_date = CURRENT_DATE AND salary_year_avg IS NULL) 
            / NULLIF((SELECT COUNT(*) FROM job_postings_fact WHERE job_posted_date = CURRENT_DATE), 0), 2), '%')
  FROM (SELECT 1)
);
```

## Notes

- **Thresholds need context, not cargo cult.** A 10% row drop might be normal for weekends but critical on Tuesdays. Baseline against relevant history, not a magic number.
- **Alerting fatigue kills monitoring.** Alert only on actionable, high-confidence signals. Tuning thresholds is harder than writing the query.
- **Connects to**: data contracts (what *should* the pipeline produce?), observability tooling (Datadog, Monte Carlo, Great Expectations), and SLA definitions.
- **Common mistake:** Monitoring only the happy path. Track failures, retries, partial loads, and schema drifts—not just "did it run?"
- **Revisit:** Once dashboards are live, treat them like code. Document *why* each alert exists, who owns it, and what the runbook is.
