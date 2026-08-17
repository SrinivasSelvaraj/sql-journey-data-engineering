---
date: 2026-08-17
phase: reliability
topic: Documentation that people actually read
---

# Documentation that people actually read

*Quality, reliability and the professional layer*

## Concept

Documentation that gets read is written *for the person who will maintain your code at 2am during an outage*, not for you. It answers: Why does this exist? What breaks if it fails? What should I know before changing it? Most pipeline documentation fails because it describes *what* the code does (which people can read from the code) rather than *why* it exists and *what assumptions it makes*.

The difference between a junior pipeline builder and someone trusted to own infrastructure is this: junior engineers assume their code is self-explanatory. Owners write for knowledge transfer. They document the business rule that required a specific join order, the data quality checks that prevented the last three production incidents, and the exact SLA the downstream team depends on. Without this, every incident becomes a full investigation, every handoff requires a meeting, and every schema change risks cascading failures.

Documentation becomes critical when the pipeline touches data others depend on, when latency or correctness failures have business cost, or when multiple people will touch the code. A small internal ETL might not need it. A fact table powering revenue reports absolutely does.

## Practice

**Problem:** The job_postings_fact table has a job_posted_date column, but sometimes it's NULL. You need to document why, what happens downstream, and when it's safe to filter it out.

```sql
-- job_postings_fact: Daily snapshot of job postings
-- OWNER: Data Platform Team | LAST UPDATED: 2025-01-15
--
-- PURPOSE:
--   Core fact table for hiring analytics. Used by reporting/BI and revenue models.
--   Upstream: web scraping pipeline (external job boards)
--   Downstream: jobs_analytics_dashboard, revenue_forecast_model
--
-- CRITICAL BUSINESS RULES:
--   - job_posted_date may be NULL if source system didn't provide it (~3% of rows)
--   - Do NOT filter WHERE job_posted_date IS NOT NULL without alerting analytics team
--   - Salary data only available for US postings; job_work_from_home reflects company policy, not guarantee
--
-- SLA: Complete by 06:00 UTC daily. If missing >24 hours, revenue model alerts.
--
-- SCHEMA NOTES:
--   - job_id: Unique per source per day (can repeat across days if reposted)
--   - salary_year_avg: Cleaned/normalized to USD. Outliers >$500k manually reviewed.
--   - job_work_from_home: TRUE only if explicitly stated; NULL means unknown, treat as FALSE in aggregations
--
-- KNOWN ISSUES:
--   - job_location contains raw text; use location_dimension for standardized joins
--   - Duplicates possible on rerun—use MAX(job_posted_date) when deduping

SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  COALESCE(job_posted_date, CURRENT_DATE - 1) AS job_posted_date_imputed -- See "KNOWN ISSUES" above
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - 30;
```

## Notes

- **Comment the "why," not the "what":** `-- Filter to last 30 days because revenue model only uses recent postings` beats `-- Get last 30 days of data`.
- **Document assumptions explicitly:** NULL handling, upstream data quality issues, business rule exceptions. These are the things that break systems at scale.
- **Link to SLAs, ownership, and downstream users.** When an analyst's dashboard breaks, they need to know who to contact and what the contract was.
- **Treat documentation as code:** Version it, review it in PRs, update it when business rules change. Stale docs are worse than no docs.
- **Connect to:** monitoring (alert when assumptions break), schema governance (document which columns are safe to modify), and incident post-mortems (document what you learned so the next person doesn't repeat it).
