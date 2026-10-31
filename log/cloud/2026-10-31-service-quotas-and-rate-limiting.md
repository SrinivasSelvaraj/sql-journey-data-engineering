---
date: 2026-10-31
phase: cloud
topic: Service quotas and rate limiting
---

# Service quotas and rate limiting

*Cloud platforms and storage*

## Concept

Service quotas and rate limiting are hard caps or throttling mechanisms that cloud platforms impose to protect infrastructure stability, ensure fair resource allocation, and enforce billing tiers. Without them, a single runaway query or misconfigured pipeline could consume all available resources, starving other tenants and causing cascading failures. You encounter quotas on API calls per second (BigQuery, Snowflake), concurrent query slots, data transfer volumes, and storage egress bandwidth. Rate limiting differs slightly—it actively slows your requests rather than rejecting them outright, buying time for the system to catch up. Understanding these constraints is essential because a slow query is often not a slow query; it's a queued query waiting for quota availability.

## Practice

**Problem:** Your team runs an hourly job that filters job_postings_fact for high-paying remote roles. In production, the query succeeds but takes 5× longer than in development. The query itself hasn't changed, and table size is stable. You suspect quota exhaustion during business hours.

```sql
-- Inefficient: scans entire table, may be queued behind other jobs
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND salary_year_avg > 120000
ORDER BY salary_year_avg DESC;

-- Better: add partition pruning and reduce columns to lower slot consumption
-- Assume job_posted_date is a clustering key for cost control
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE() - INTERVAL 90 DAY
  AND job_work_from_home = TRUE
  AND salary_year_avg > 120000
ORDER BY salary_year_avg DESC
LIMIT 1000;  -- Explicit limit signals intent, helps scheduler prioritize
```

## Notes

- **Confuse slow queries with quota queuing:** Run the same query at off-peak hours to isolate whether latency is computation or contention. Cloud platform job logs show queue time separately.
- **Overlook burst vs. sustained limits:** You may have 1,000 requests/sec burst capacity but only 100 req/sec sustained. Spike protection can mask quota problems until they accumulate.
- **Related: cost attribution and chargeback models.** Quotas often map directly to billing units (slots, API calls, GB scanned). Tracking quota use trains you to spot runaway costs.
- **Adjacent: autoscaling and reserved capacity.** Most platforms let you buy reserved slots or autoscale on-demand; choose based on your job's predictability and cost tolerance.
- **Worth revisiting: monitoring dashboards and alerting.** Set alerts at 70–80% quota use so you catch problems before they degrade user experience.
