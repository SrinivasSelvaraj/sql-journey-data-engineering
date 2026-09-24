---
date: 2026-09-24
phase: cloud
topic: Service quotas and soft limits escalation
---

# Service quotas and soft limits escalation

*Cloud platforms and storage*

## Concept

Service quotas are hard limits (or soft limits with escalation paths) imposed by cloud providers to protect infrastructure stability and enforce billing fairness. They constrain resources like API calls per second, concurrent queries, storage throughput, or row scans per second. When you hit a quota, requests fail with rate-limit or capacity errors—your pipeline stalls, your query times out, and your team loses visibility into whether the slowdown is bad code or a ceiling you've bumped.

Soft limits can usually be escalated by filing a support request; hard limits require architectural changes. Understanding your provider's quotas prevents surprises: a BigQuery query scanning 10 TB might hit per-slot query limits; a Redshift cluster at 100% CPU will queue new connections; Snowflake's credit consumption accelerates if you don't partition or cluster properly. The cost question ("why am I being billed $500 for that job?") is often answered by finding you ran unoptimized scans that consumed quota and credits unnecessarily.

Without quota awareness, you design inefficient pipelines in dev, ship them to prod, and only discover the bottleneck when users complain. Proactive quota management means knowing your limits, monitoring usage, and escalating early for legitimate growth rather than scrambling when production breaks.

## Practice

**Problem:** Your hiring analytics job scans `job_postings_fact` daily to calculate salary trends by location. The query is unfiltered and scans every row every run, consuming 50 GB per execution. Your Snowflake warehouse is running into per-query credit limits and getting throttled. How do you optimize to stay under quota and reduce cost?

```sql
-- BEFORE: Unfiltered scan, high quota consumption
SELECT 
  job_location,
  AVG(salary_year_avg) AS avg_salary,
  COUNT(*) AS job_count
FROM job_postings_fact
GROUP BY job_location
ORDER BY avg_salary DESC;

-- AFTER: Partition on job_posted_date, filter to recent data
SELECT 
  job_location,
  AVG(salary_year_avg) AS avg_salary,
  COUNT(*) AS job_count
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
  AND salary_year_avg IS NOT NULL
GROUP BY job_location
ORDER BY avg_salary DESC;

-- BONUS: Materialize incrementally to avoid rescanning
CREATE OR REPLACE TABLE job_salary_summary AS
SELECT 
  job_location,
  MAX(job_posted_date) AS last_updated,
  AVG(salary_year_avg) AS avg_salary,
  COUNT(*) AS job_count
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY job_location;
```

## Notes

- **Quota blindness in dev:** Testing on small datasets masks quota issues; always estimate production data volume and query cost before scaling up.
- **Soft vs. hard limits:** Soft limits (e.g., Snowflake concurrent queries) escalate quickly; hard limits (e.g., API throughput) require code redesign—know which you're hitting.
- **Connects to:** cost allocation, query optimization, data partitioning, and monitoring dashboards—quota management is inseparable from performance tuning.
- **Common mistake:** Assuming query speed = correctness; a fast-but-expensive query that burns quota is still broken in production.
- **Revisit:** Provider-specific quota pages quarterly; cloud limits change, and your data volume grows—what was safe in Q1 may not be in Q4.
