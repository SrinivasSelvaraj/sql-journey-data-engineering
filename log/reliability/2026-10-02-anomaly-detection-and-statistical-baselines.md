---
date: 2026-10-02
phase: reliability
topic: Anomaly detection and statistical baselines
---

# Anomaly detection and statistical baselines

*Quality, reliability and the professional layer*

## Concept

Anomaly detection establishes statistical baselines—expected ranges, distributions, and patterns in your data—then flags deviations that warrant investigation. This is the operational heartbeat of owned pipelines: knowing not just *that* data arrived, but whether it arrived *correctly*. Without baselines, you're flying blind on data quality; you'll discover corrupt ETL logic only when it hits dashboards or reports, not when it enters the warehouse.

The practical stakes are high. A salary field that suddenly drops 40% average, a job posting volume that halts mid-week, or a location field that shifts to 60% NULL—these aren't just metrics that changed; they're signals your upstream source, transformation logic, or business itself has shifted in ways you need to know *immediately*. Baselines let you distinguish signal from noise: is this a real market shift or a schema break?

Building baselines means calculating percentiles, z-scores, or growth thresholds on historical data, then comparing fresh loads against them. It's not about perfection; it's about *expected* bounds and *triggering investigation* when you breach them.

## Practice

**Problem:** The job_postings_fact table loads daily. You need to detect if today's load is anomalous in three ways: (1) total volume is down >20% from the 30-day rolling average, (2) average salary for 'Data Engineer' roles dropped >15%, or (3) the proportion of work-from-home postings jumped >10 percentage points.

```sql
WITH baseline AS (
  SELECT
    DATE_TRUNC('day', job_posted_date)::DATE AS load_date,
    COUNT(*) AS daily_volume,
    AVG(CASE WHEN job_title_short = 'Data Engineer' THEN salary_year_avg END) AS de_avg_salary,
    SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END)::FLOAT / COUNT(*) AS wfh_proportion
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - 30
  GROUP BY 1
),
rolling_baseline AS (
  SELECT
    AVG(daily_volume) AS vol_baseline,
    STDDEV(daily_volume) AS vol_stddev,
    AVG(de_avg_salary) AS salary_baseline,
    AVG(wfh_proportion) AS wfh_baseline
  FROM baseline
  WHERE load_date < CURRENT_DATE
),
today AS (
  SELECT
    COUNT(*) AS daily_volume,
    AVG(CASE WHEN job_title_short = 'Data Engineer' THEN salary_year_avg END) AS de_avg_salary,
    SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END)::FLOAT / COUNT(*) AS wfh_proportion
  FROM job_postings_fact
  WHERE job_posted_date = CURRENT_DATE
)
SELECT
  today.daily_volume,
  rolling_baseline.vol_baseline,
  ROUND(100.0 * (1 - today.daily_volume / rolling_baseline.vol_baseline), 1) AS volume_pct_drop,
  CASE WHEN today.daily_volume < rolling_baseline.vol_baseline * 0.8 THEN 'ALERT' ELSE 'OK' END AS volume_status,
  today.de_avg_salary,
  rolling_baseline.salary_baseline,
  ROUND(100.0 * (1 - today.de_avg_salary / rolling_baseline.salary_baseline), 1) AS salary_pct_drop,
  CASE WHEN today.de_avg_salary < rolling_baseline.salary_baseline * 0.85 THEN 'ALERT' ELSE 'OK' END AS salary_status,
  ROUND(100.0 * (today.wfh_proportion - rolling_baseline.wfh_baseline), 1) AS wfh_pct_point_change,
  CASE WHEN ABS(today.wfh_proportion - rolling_baseline.wfh_baseline) > 0.10 THEN 'ALERT' ELSE 'OK' END AS wfh_status
FROM today, rolling_baseline;
```

## Notes

- **Baseline window matters**: 30 days captures weekly cycles; too short and you're chasing noise, too long and you miss emerging shifts. Seasonality (hiring seasons, fiscal quarters) requires domain knowledge—don't use fixed windows blindly.

- **Alert fatigue kills ownership**: If every 5% variance triggers an alert, you'll ignore them. Set thresholds conservatively; start at ±2 standard deviations or domain-meaningful bounds (e.g., "salary never drops >10%"), then tighten as you learn your data's true behavior.

- **Connects to data contracts and SLAs**: Anomaly detection operationalizes the promise you're making downstream. "This table will have ±5% daily volume with <2% nulls in salary" becomes testable, automated, and forms the
