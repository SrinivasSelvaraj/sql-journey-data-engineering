---
date: 2026-09-30
phase: reliability
topic: Custom metrics: business domain and technical health
---

# Custom metrics: business domain and technical health

*Quality, reliability and the professional layer*

## Concept

Custom metrics bridge the gap between pipeline execution and business impact. They answer two distinct questions: *Is the data correct?* (technical health) and *Does it serve the business?* (domain value). A pipeline can run successfully, produce zero errors, and still fail spectacularly—delivering stale salary data when market rates shift daily, or missing remote work opportunities because location parsing broke silently.

Technical health metrics monitor the pipeline itself: latency, freshness, completeness, schema compliance. Business domain metrics measure whether the data actually solves the problem it was built for—salary competitiveness within ±5%, work-from-home filtering accuracy, location coverage in target markets. Without custom metrics, you discover problems through user complaints or dashboard gaps. With them, you own the outcome.

The difference between "pipeline builder" and "pipeline owner" is accountability. Owners define what success looks like before failure happens, instrument it into alerts, and track it obsessively. This requires understanding not just the data flow, but the business decision that depends on it.

## Practice

**Problem:** A job postings pipeline publishes salary and remote work data daily. Engineering tracks job_count and load_duration—both green. But the recruiting team reports that salary values for tech roles are increasingly inaccurate (often null or outdated), and remote work flags flip inconsistently. How do you detect this before users notice?

```sql
-- Technical health: freshness and completeness
CREATE OR REPLACE TABLE job_postings_metrics AS
SELECT
  DATE(CURRENT_TIMESTAMP()) as metric_date,
  COUNT(*) as total_jobs,
  COUNTIF(salary_year_avg IS NULL) as null_salary_count,
  ROUND(COUNTIF(salary_year_avg IS NULL) / COUNT(*), 3) as salary_null_rate,
  MAX(job_posted_date) as latest_job_posted,
  DATE_DIFF(DATE(CURRENT_TIMESTAMP()), MAX(job_posted_date), DAY) as max_age_days,
  COUNTIF(job_posted_date < DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)) as jobs_older_than_7d
FROM job_postings_fact
GROUP BY metric_date;

-- Business domain: accuracy and consistency checks
CREATE OR REPLACE TABLE job_postings_domain_metrics AS
SELECT
  DATE(CURRENT_TIMESTAMP()) as metric_date,
  job_title_short,
  COUNT(*) as title_job_count,
  ROUND(AVG(salary_year_avg), 0) as avg_salary,
  COUNTIF(salary_year_avg IS NULL) as missing_salary_by_title,
  ROUND(COUNTIF(job_work_from_home = TRUE) / COUNT(*), 3) as remote_pct,
  -- Detect anomalies: if average salary drops >20% day-over-day, flag it
  CASE WHEN AVG(salary_year_avg) < 80000 THEN 'LOW_SALARY_ALERT' ELSE 'OK' END as salary_health
FROM job_postings_fact
WHERE job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
GROUP BY metric_date, job_title_short;

-- Alert when domain metrics drift
SELECT * FROM job_postings_domain_metrics
WHERE salary_null_rate > 0.15 OR salary_health = 'LOW_SALARY_ALERT';
```

## Notes

- **Mistake:** Treating technical metrics (row count, latency) as sufficient. A pipeline can be fast and complete but wrong—null salaries are still rows.
- **Mistake:** Metrics without thresholds. Define "acceptable" salary null rate (e.g., <5%) and remote work consistency before instrumenting; otherwise you collect noise.
- **Connection:** This feeds directly into SLA definition and observability. Custom metrics become the contract between data engineering and stakeholders.
- **Adjacent:** Data quality frameworks (Great Expectations, dbt tests) validate structure; custom metrics validate *meaning*. Both needed.
- **Revisit:** Ownership extends to alerting strategy—who owns the alert? When do you page? Domain metrics need business context to be actionable.
