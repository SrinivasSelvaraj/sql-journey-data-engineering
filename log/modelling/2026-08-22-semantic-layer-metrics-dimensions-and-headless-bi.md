---
date: 2026-08-22
phase: modelling
topic: Semantic layer: metrics, dimensions and headless BI
---

# Semantic layer: metrics, dimensions and headless BI

*Data modelling and warehousing*

## Concept

A semantic layer sits between raw data and analytics tools, defining **metrics** (calculations like revenue, churn rate, average salary) and **dimensions** (categorical attributes like job title, location, hire date) in a single source of truth. Without it, every analyst writes their own salary calculation or definitions—leading to conflicting reports and the famous "why do sales and finance have different numbers?" problem. The semantic layer codifies business logic once so queries become simpler (`SELECT revenue FROM metrics` instead of `SELECT SUM(amount * quantity) FROM orders WHERE...`) and consistent across tools.

A headless BI approach decouples this semantic layer from any single BI tool (Tableau, Looker, Power BI). Teams query the layer directly via SQL or APIs, letting different tools—dashboards, notebooks, reports—use the same metrics. This matters when you have mixed tooling or when you want analysts to self-serve without rebuilding logic in every platform. Without it, you're locked into one vendor's definition of "revenue" and must rebuild metrics when you switch tools.

## Practice

**Problem:** Your analytics team needs to compare average salary by job location and remote status, but different people calculate "average salary" differently—some include nulls, some exclude outliers, some use median instead. You need one definition.

```sql
CREATE VIEW job_metrics AS
SELECT
  job_location AS location_dimension,
  job_work_from_home AS remote_dimension,
  COUNT(*) AS posting_count_metric,
  ROUND(AVG(CASE WHEN salary_year_avg > 0 THEN salary_year_avg END), 2) AS avg_salary_metric,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) AS median_salary_metric,
  MAX(job_posted_date) AS latest_posting_date_metric
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY job_location, job_work_from_home;

-- Now any analyst queries the layer, not the raw fact table:
SELECT location_dimension, remote_dimension, avg_salary_metric
FROM job_metrics
ORDER BY avg_salary_metric DESC;
```

## Notes

- **Metric naming matters**: Prefix metrics (e.g., `avg_salary_metric`) and dimensions (e.g., `location_dimension`) so consumers know what they're grabbing and whether it's calculated or raw.
- **Null handling is business logic**: Decide once whether `NULL salary_year_avg` means "excluded from average" or "zero"—embed that choice in the semantic layer, not in 50 ad-hoc queries.
- **Connect to dbt**: Semantic layers often live as dbt models (`{{ ref('job_metrics') }}`), making them version-controlled and testable; tools like dbt Semantic Layer add a query API on top.
- **Headless BI vs. embedded BI**: Headless lets you swap visualization tools; embedded locks you to one vendor but may be faster for small teams. Start headless if you're building for scale.
- **Revisit grain and aggregation**: A metric must have a clear grain (per location? per location + date?). Changing grain mid-analysis breaks joins; define it upfront in the view or dbt model.
