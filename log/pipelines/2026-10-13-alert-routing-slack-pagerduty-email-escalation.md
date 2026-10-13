---
date: 2026-10-13
phase: pipelines
topic: Alert routing: Slack, PagerDuty, email escalation
---

# Alert routing: Slack, PagerDuty, email escalation

*Pipelines and orchestration*

## Concept

Alert routing directs pipeline failures to the right person at the right time through the right channel. When a data job fails silently or sends all alerts to email, you lose hours to discovery lag and miss critical SLAs. Without routing logic, a non-urgent data refresh and a broken revenue pipeline both ping Slack at 3 AM—creating either alert fatigue or critical blindness.

Effective routing stratifies by severity and audience: syntax errors and late-arriving data go to Slack during business hours; schema breaks and missing critical columns trigger PagerDuty escalation; compliance failures page on-call engineers immediately. The routing decision happens at pipeline orchestration time (Airflow, dbt Cloud, Prefect), not after the fact, so the alert lands in the right place before your team knows to look.

Without this, data teams either disable alerts (and miss real issues) or treat all alerts the same (and burn out on noise). Routing is your circuit breaker between transparency and sanity.

## Practice

**Problem:** A job_postings_fact daily refresh fails when salary_year_avg contains null values above a 5% threshold. You need salary nulls logged to Slack for analysis, but missing job_location entirely should page the on-call engineer via PagerDuty because downstream recruiting dashboards depend on it.

```sql
-- Alert routing decision logic in your orchestration layer (pseudocode + SQL)
WITH data_quality_checks AS (
  SELECT
    'salary_nulls' AS check_name,
    ROUND(100.0 * SUM(CASE WHEN salary_year_avg IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS null_pct,
    CASE 
      WHEN ROUND(100.0 * SUM(CASE WHEN salary_year_avg IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) > 5 
      THEN 'slack_warning'
      ELSE 'pass'
    END AS alert_route
  FROM job_postings_fact
  WHERE job_posted_date = CURRENT_DATE
  
  UNION ALL
  
  SELECT
    'location_nulls' AS check_name,
    ROUND(100.0 * SUM(CASE WHEN job_location IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS null_pct,
    CASE 
      WHEN SUM(CASE WHEN job_location IS NULL THEN 1 ELSE 0 END) > 0 
      THEN 'pagerduty_critical'
      ELSE 'pass'
    END AS alert_route
  FROM job_postings_fact
  WHERE job_posted_date = CURRENT_DATE
)
SELECT check_name, null_pct, alert_route
FROM data_quality_checks
WHERE alert_route != 'pass';

-- In Airflow/dbt: capture this result and route
-- IF alert_route = 'pagerduty_critical' → trigger PagerDuty webhook + email on-call
-- IF alert_route = 'slack_warning' → send to #data-quality Slack channel
-- ELSE → silent pass, log to monitoring table
```

## Notes

- **Severity ≠ channel.** A slow query is urgent for engineering but informational for analytics; route by impact, not just error type.
- **Escalation paths matter.** Slack is for async awareness; PagerDuty for time-sensitive (SLA-bound) issues; email for audit trails. Layer them.
- **Avoid alert fatigue by tuning thresholds ruthlessly.** A 5% null threshold on salary will fire weekly; you'll ignore it. Start conservative, expand only after you've acted on the alert three times.
- **Connects to:** data quality frameworks (Great Expectations, dbt tests), observability/monitoring (Datadog, New Relic), incident response runbooks (who owns what when the page fires).
- **Revisit when:** adding new downstream consumers, after a missed critical failure, or when your on-call rotation changes—routing assumptions decay fast.
