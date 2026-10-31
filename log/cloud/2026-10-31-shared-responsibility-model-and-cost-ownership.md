---
date: 2026-10-31
phase: cloud
topic: Shared responsibility model and cost ownership
---

# Shared responsibility model and cost ownership

*Cloud platforms and storage*

## Concept

The shared responsibility model defines which party—cloud provider or customer—owns costs and performance for different layers of infrastructure. As a data engineer, you control *what* queries run and *how* they access data (indexing, partitioning, materialization), while the provider controls hardware, network, and query execution engine. Without clarity, slow queries get blamed on "the system" when the real issue is an unoptimized scan, or expensive bills arrive because no one partitioned a 500GB table.

Cost ownership means understanding *why* each query costs what it does. On BigQuery, scanning 1TB costs the same whether you filter 1 row or 1 billion rows—so full-table scans are expensive by design. On Redshift, you pay for cluster uptime regardless of query count, making batch efficiency critical. On Snowflare, compute and storage are separate line items. Knowing your platform's pricing model lets you make trade-offs: cache aggressively or partition aggressively? Materialize or compute on-the-fly?

## Practice

**Problem:** A daily reporting query scans the entire `job_postings_fact` table (~2TB) to filter for last week's posts, costing $10/day in query charges. The table grows continuously and will hit $300/month. Assuming BigQuery-style per-TB scanning, how do you reduce costs?

```sql
-- BEFORE: Full table scan every run
SELECT 
  job_title_short, 
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE() - INTERVAL 7 DAY
GROUP BY job_title_short;

-- AFTER: Partition on job_posted_date, only scan last 7 days
CREATE OR REPLACE TABLE job_postings_fact
PARTITION BY DATE(job_posted_date)
CLUSTER BY job_title_short
AS SELECT * FROM job_postings_fact;

-- Query now scans ~28GB (7 days) instead of 2TB
SELECT 
  job_title_short, 
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE() - INTERVAL 7 DAY
GROUP BY job_title_short;
```

The partition pruning cuts scanning 70×, dropping cost to $0.14/day.

## Notes

- **Scanning ≠ returning**: BigQuery charges for data *scanned*, not returned. A query filtering 1M rows from 1TB still costs the same unless partitioning/clustering eliminates blocks before scanning.
- **Know your pricing model**: per-compute-second (Redshift, Spark), per-GB-scanned (BigQuery), per-compute-credit (Snowflake), or per-instance-hour (managed Postgres)—each incentivizes different optimization strategies.
- **Materialization is a cost trade-off**: storing pre-aggregated tables uses storage ($0.02–0.05/GB/month) to avoid repeated compute ($5–50 per query). Calculate break-even: does a view run >5 times/week?
- **Responsibility boundary**: You own schema design, query logic, and access patterns. The provider owns query planner and infrastructure—but you must *audit* the planner's choices (check `EXPLAIN` output for full scans).
- **Monitor and alert**: Set up cost dashboards by query, user, or project. A single unoptimized join or uncapped GROUP BY can spike a $5k monthly bill in hours.
