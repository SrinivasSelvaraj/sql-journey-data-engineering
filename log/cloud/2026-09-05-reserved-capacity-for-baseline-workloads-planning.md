---
date: 2026-09-05
phase: cloud
topic: Reserved capacity for baseline workloads planning
---

# Reserved capacity for baseline workloads planning

*Cloud platforms and storage*

## Concept

Reserved capacity allocates compute resources for predictable baseline workloads, reducing per-query costs by 25–70% compared to on-demand pricing. On platforms like BigQuery (annual/monthly slots) or Redshift (reserved nodes), you commit to a minimum resource tier and pay upfront, then run queries within that allocation without per-GB scanning charges or additional execution fees. This matters when you have repeatable ETL jobs, dashboards, or reporting pipelines that consume predictable query volume—not for one-off ad hoc analysis.

Without reserved capacity, slow queries often stem from resource contention: your query queues behind others when the cluster reaches capacity, or query cost spirals unpredictably when data volume grows. You lose visibility into *why* a query slowed down—whether it was genuinely inefficient SQL, or simply starved of compute. Reserved capacity forces you to right-size your baseline: if you reserve too little, you still hit queueing; too much, and you waste money on idle slots.

## Practice

**Problem:** Your analytics team runs daily reports on job postings (filtering by location, aggregating salary by job_title_short). In the past month, morning reports started failing or timing out, and on-demand query costs doubled. You need to determine if reserved capacity would help and how much to buy.

```sql
-- Establish baseline: daily query volume and typical execution time
SELECT
  DATE(job_posted_date) AS report_date,
  COUNT(DISTINCT job_id) AS jobs_scanned,
  APPROX_QUANTILES(job_posted_date, 100)[OFFSET(50)] AS p50_date
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE() - INTERVAL 30 DAY
GROUP BY report_date
ORDER BY report_date DESC;

-- Simulate your typical morning report query
SELECT
  job_location,
  job_title_short,
  COUNT(*) AS posting_count,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE() - INTERVAL 7 DAY
  AND job_work_from_home = FALSE
GROUP BY job_location, job_title_short
HAVING COUNT(*) > 10
ORDER BY posting_count DESC;

-- Cost analysis: if query scans 500GB daily and on-demand = $6.25/TB,
-- annual on-demand cost = 500GB * 365 * $6.25/1000 = $1,141.
-- BigQuery annual slot (100 slots @ $2000/month) = $24,000,
-- break-even at ~2.1TB scanned/day. If you scan 500GB/day,
-- reserved capacity is not yet justified; optimize query first.
```

## Notes

- **Slot saturation is invisible in query logs:** a query that "took 8 minutes" may have spent 7 minutes queued. Reserve only after confirming bottleneck with platform monitoring (BigQuery BI Engine, Redshift CloudWatch metrics).
- **Right-sizing requires 2–4 weeks of baseline data:** track peak concurrent queries, not just daily volume. A dashboard refreshing at 6 AM across 20 reports needs simultaneous slots; one report per hour needs far fewer.
- **Reserved vs. on-demand trade-off:** reserve the *minimum* predictable load (e.g., core ETL + executive dashboards), burst on-demand for ad hoc queries and data exploration.
- **Storage and compute are separate:** reserved capacity (slots/nodes) does not include storage scans; query optimization (partitioning, clustering, column pruning) saves money *before* you commit to capacity.
- **Adjacent topic:** commitment discounts for storage (e.g., BigQuery annual storage pricing) and slot autoscaling policies interact with capacity planning—reserve slots intelligently, not defensively.
