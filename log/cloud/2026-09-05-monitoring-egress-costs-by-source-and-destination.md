---
date: 2026-09-05
phase: cloud
topic: Monitoring egress costs by source and destination
---

# Monitoring egress costs by source and destination

*Cloud platforms and storage*

## Concept

Egress costs—data leaving your cloud platform—often dwarf compute and storage costs but remain invisible without explicit monitoring. Unlike ingress (free on most clouds) or inter-region transfers (sometimes cheaper), egress to the internet or across regions can cost $0.02–$0.12 per GB. You need to track *where* data is going and *why* to catch runaway queries pulling large result sets to external systems, cross-region joins materializing full tables, or misconfigured ETL pipelines exporting unnecessarily.

Without source-and-destination visibility, a single poorly tuned report query shipping 500 GB to a BI tool, or a data lake scan replicating tables across regions, can incur thousands in surprise bills before anyone notices. The query runs "fine" from a latency perspective but hemorrhages cost. Monitoring by source (which table, which region's storage) and destination (internet, another region, another cloud) lets you pinpoint the culprit and decide: filter earlier, cache results, or push computation closer to data.

## Practice

**Problem:** Your job postings fact table is in `us-east-1`. You notice egress costs spiking but don't know which dashboards or reports are pulling data out-of-region. Write a query that identifies jobs posted in high-salary ranges by location, but structure it to minimize egress by filtering and aggregating *before* returning results, and add a comment explaining what egress sink this avoids.

```sql
-- Aggregates locally in us-east-1 before returning results
-- Avoids egress: returns ~100 rows instead of millions to external BI tool
SELECT
  job_location,
  job_work_from_home,
  COUNT(*) as job_count,
  ROUND(AVG(salary_year_avg), 2) as avg_salary,
  MAX(salary_year_avg) as max_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY
  AND salary_year_avg > 150000  -- filter early
  AND job_title_short IN ('Data Engineer', 'Senior Data Engineer')  -- narrow scope
GROUP BY job_location, job_work_from_home
HAVING COUNT(*) > 5  -- eliminate sparse groups before export
ORDER BY avg_salary DESC;
```

## Notes

- **Query cost ≠ egress cost**: a cheap query (low compute) can still export expensive data; always `LIMIT`, aggregate, or filter before `SELECT *`.
- **Cross-region and multi-cloud egress differ**: AWS charges less for same-region access; Azure may charge differently to internet vs. peering partner; document your platform's tier.
- **Materialized views and caching**: if the same large export runs repeatedly, cache or materialize it locally to avoid repeated egress; often cheaper than query optimization alone.
- **Combine with query logs**: correlate slow queries + high egress via your platform's audit logs (CloudTrail, query history) to assign egress to teams/dashboards.
- **Adjacent: data residency and compliance**: egress monitoring often overlaps with regulatory requirements (GDPR, HIPAA) that restrict where sensitive data can leave.
