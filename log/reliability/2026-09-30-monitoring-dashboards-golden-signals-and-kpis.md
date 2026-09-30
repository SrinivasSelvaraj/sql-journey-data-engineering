---
date: 2026-09-30
phase: reliability
topic: Monitoring dashboards: golden signals and KPIs
---

# Monitoring dashboards: golden signals and KPIs

*Quality, reliability and the professional layer*

## Concept

Golden signals are the four fundamental metrics that reveal system health: latency, traffic, errors, and saturation. In data engineering, these translate to pipeline execution time, data volume processed, failed transforms or loads, and resource utilization. KPIs (key performance indicators) sit above golden signals—they're business-aligned measures like "daily active users loaded" or "report freshness SLA compliance" that connect infrastructure health to outcome value.

Without monitoring these systematically, you discover problems through complaints: reports go stale, stakeholders lose trust, and you're constantly firefighting instead of improving. A dashboard tracking golden signals lets you catch degradation *before* it becomes an incident. This is the difference between building a pipeline that works today and owning one that works reliably for years.

The professional layer means shifting from "did this run?" to "did this run *well*?" A senior engineer owns latency budgets, error budgets, and SLA commitments. You're no longer reacting; you're predicting and preventing.

## Practice

**Problem:** Your job_postings pipeline runs daily, but you have no visibility into whether it's healthy. You need a dashboard that tracks: (1) how many jobs were loaded, (2) whether the load completed on time, (3) if salary data is present for jobs that should have it, and (4) lag between posting date and load date.

```sql
-- Create a monitoring view for golden signals + KPIs
CREATE VIEW pipeline_monitoring AS
SELECT
  CURRENT_DATE as monitor_date,
  COUNT(*) as jobs_loaded,  -- TRAFFIC
  COUNT(CASE WHEN salary_year_avg IS NOT NULL THEN 1 END) as jobs_with_salary,
  ROUND(100.0 * COUNT(CASE WHEN salary_year_avg IS NOT NULL THEN 1 END) / COUNT(*), 2) as salary_completeness_pct,  -- KPI
  MAX(DATEDIFF(DAY, job_posted_date, CURRENT_DATE)) as max_lag_days,  -- LATENCY
  AVG(DATEDIFF(DAY, job_posted_date, CURRENT_DATE)) as avg_lag_days,
  COUNT(CASE WHEN job_location IS NULL THEN 1 END) as null_location_count  -- ERROR signal
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - 7
GROUP BY CURRENT_DATE;

-- Alert threshold: flag if salary_completeness drops below 85% or avg lag exceeds 2 days
SELECT * FROM pipeline_monitoring
WHERE salary_completeness_pct < 85 OR avg_lag_days > 2;
```

## Notes

- **Golden signals vs. KPIs confusion:** Golden signals diagnose *how* the system is running; KPIs measure *whether* it matters. You need both—latency is useless if no one depends on freshness, and a KPI is meaningless if you can't explain why it changed.

- **Common mistake:** Tracking metrics without thresholds or runbooks. A dashboard that only reports numbers is decoration. Pair every metric with "what value is acceptable?" and "who gets alerted if it breaches?"

- **Connects to:** SLA/SLO definitions (what commit are you making to users?), alerting/incident response (what happens when a metric crosses the line?), and cost optimization (saturation metrics reveal where you're spending unnecessarily).

- **Revisit:** Data quality gates (are you catching bad data in your KPI calculations?), observability in code (logging + instrumentation in your transforms), and aggregation pitfalls (make sure your monitoring query doesn't silently miss failures).

- **Ownership mindset:** A pipeline you own should have more monitoring than code you write. You're trading explicit visibility for implicit reliability.
