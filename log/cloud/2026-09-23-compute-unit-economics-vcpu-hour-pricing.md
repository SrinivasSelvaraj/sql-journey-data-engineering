---
date: 2026-09-23
phase: cloud
topic: Compute unit economics: vCPU hour pricing
---

# Compute unit economics: vCPU hour pricing

*Cloud platforms and storage*

## Concept

vCPU hour pricing is the fundamental cost model for cloud compute—you pay for each virtual CPU core running for each hour (or fractional hour). On platforms like AWS, GCP, and Azure, this rate varies by instance type, region, and commitment model. A query that scans 10 billion rows using 16 vCPUs for 5 minutes costs differently than one using 2 vCPUs for 30 minutes, even if total work is similar. Understanding this matters because slow queries don't just take longer—they consume more vCPU-hours, multiplying cost. Without tracking this, teams routinely optimize for query *latency* (how fast it finishes) while ignoring *efficiency* (CPU resource consumed per gigabyte processed), leading to expensive production workloads that "complete quickly" by throwing hardware at the problem.

The relationship between query complexity and vCPU cost is nonlinear. A full table scan on 100M rows with poor indexes might use 8 vCPUs for 10 minutes (1.33 vCPU-hours); a properly indexed query on the same data might use 2 vCPUs for 1 minute (0.033 vCPU-hours)—a 40× cost reduction. This is why slow queries are often *expensive* queries: they force the optimizer to do more work, and cloud platforms scale CPU allocation to match demand, so inefficiency directly translates to billing.

## Practice

**Problem:** You notice a daily report that aggregates salary statistics by job location is taking 12 minutes and consuming ~32 vCPU-hours per run (measured via platform monitoring). Your cloud bill for this single query is ~$0.40–0.50 per run. Identify and optimize the inefficiency.

```sql
-- BEFORE: Inefficient query (full scan, no filtering)
SELECT 
  job_location,
  COUNT(*) as job_count,
  AVG(salary_year_avg) as avg_salary,
  MAX(salary_year_avg) as max_salary
FROM job_postings_fact
WHERE job_work_from_home = FALSE
GROUP BY job_location
ORDER BY avg_salary DESC;

-- AFTER: Optimized query (partition pruning, indexed columns, pre-filtering)
-- Assume partitioning on job_posted_date and index on (job_work_from_home, job_location)
SELECT 
  job_location,
  COUNT(*) as job_count,
  AVG(salary_year_avg) as avg_salary,
  MAX(salary_year_avg) as max_salary
FROM job_postings_fact
WHERE job_work_from_home = FALSE
  AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days'  -- Partition pruning
GROUP BY job_location
HAVING COUNT(*) > 5  -- Filter aggregates early
ORDER BY avg_salary DESC
LIMIT 50;
```

The optimized version reduces data scanned by ~80% (partition pruning), allows the engine to use index seeks instead of table scans, and limits output rows. Expected result: 2–3 minute runtime, ~4–6 vCPU-hours, ~$0.05–0.08 per run.

## Notes

- **Confusing latency with efficiency:** A query completing in 2 minutes using 64 vCPUs is slower to run but potentially cheaper than one taking 15 minutes on 4 vCPUs. Monitor both metrics separately.
- **Ignoring region and instance-type variance:** vCPU costs differ 3–5× across regions and reserved vs. on-demand pricing. A query optimized for us-east-1 may be uneconomical in eu-west-1.
- **Overlooking data skew and partition pruning:** Most cloud platforms charge for *data scanned*, not rows returned. Queries that scan 100GB to return 1KB are common performance killers; always check partition elimination in execution plans.
- **Related topics:** query profiling (EXPLAIN ANALYZE), columnar storage and compression (Parquet, ORC reduce vCPU cost), and reserved capacity models (commit to vCPU hours in advance for 30–70% discounts).
- **Revisit:** Run cost attribution by query/user/team monthly; establish a cost-per-million-rows budget to create accountability and catch regressions early.
