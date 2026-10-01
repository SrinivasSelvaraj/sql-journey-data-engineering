---
date: 2026-10-01
phase: reliability
topic: Metric definition standards: single source of truth
---

# Metric definition standards: single source of truth

*Quality, reliability and the professional layer*

## Concept

A single source of truth (SSOT) for metrics means one authoritative definition and calculation method, owned by one team, used everywhere. Without it, Marketing calculates "active users" differently than Product, Finance reports revenue differently than Sales, and stakeholders make decisions on conflicting numbers. The cost is invisible until a board meeting where three departments cite three different figures for the same KPI.

This becomes critical once your data is consumed by more than one team or used for compliance/financial reporting. It's the difference between a pipeline engineer (who builds things) and a data engineer (who owns them)—ownership means you've standardized the definition, documented it, and created infrastructure so no one accidentally reimplements it wrong downstream.

Without SSOT, you inherit technical debt: duplicate logic scattered across dashboards and reports, metric calculations that drift over time, and debugging nightmares when someone asks "which number is right?" The fix requires governance—a metrics layer, a metric repository, or at minimum a documented contract that all consumers follow.

## Practice

**Problem:** Three teams need "average salary by job title," but they're calculating it differently. Marketing excludes remote jobs (thinking "market rate for in-office"), Finance includes all data, and Product wants only jobs posted in the last 90 days. Results conflict. How do you establish one definition?

```sql
-- Create a single metric definition, owned by Analytics
CREATE TABLE metrics.salary_benchmarks AS
SELECT 
  job_title_short,
  AVG(salary_year_avg) AS avg_salary_usd,
  COUNT(*) AS sample_size,
  CURRENT_TIMESTAMP AS metric_calculated_at
FROM job_postings_fact
WHERE 
  salary_year_avg IS NOT NULL
  AND job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY
  -- explicit: include remote and non-remote equally
GROUP BY job_title_short;

-- Document the contract
COMMENT ON TABLE metrics.salary_benchmarks IS 
'SSOT for salary benchmarks. Includes all work arrangements. 90-day rolling window. 
Recalculated daily. Owner: Analytics (analytics@company.com). 
DO NOT recalculate this metric elsewhere.';

-- All downstream consumers query this, not the raw table
SELECT job_title_short, avg_salary_usd 
FROM metrics.salary_benchmarks 
WHERE job_title_short = 'Data Engineer';
```

## Notes

- **Common mistake:** Building metric tables but not preventing raw-table queries. You need both the artifact *and* access controls (or strong social contract) so users stop reinventing it.
- **Ownership matters:** Assign one person/team as the metric owner. They handle schema changes, versioning, documentation, and support questions. This is not a shared responsibility.
- **Version your metrics:** If definition changes, create `salary_benchmarks_v2` rather than silently redefining the original. Consumers need to migrate intentionally, not break mid-quarter.
- **Connect to:** data contracts, metric repositories (like dbt Metrics or Cube), and your data catalog. SSOT requires discoverability—if no one knows the metric exists, they'll rebuild it.
- **Revisit:** How do you handle metric SLA violations (e.g., "this should refresh by 6 AM")? That's ownership too.
