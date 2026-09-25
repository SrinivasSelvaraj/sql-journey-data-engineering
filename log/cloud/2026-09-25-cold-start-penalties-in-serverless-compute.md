---
date: 2026-09-25
phase: cloud
topic: Cold start penalties in serverless compute
---

# Cold start penalties in serverless compute

*Cloud platforms and storage*

## Concept

A cold start occurs when a serverless function (Lambda, Cloud Functions, etc.) must initialize a new container before executing your query. This adds latency—typically 1–5 seconds for the first invocation, or after the function has been idle. In data engineering, cold starts matter most when you have unpredictable traffic patterns, long gaps between queries, or auto-scaling that spins down unused instances.

The cost impact is indirect but real: a cold start doesn't charge extra compute, but it does waste wall-clock time. If your batch job waits 3 seconds per cold start across 10 parallel functions, you've added 30 seconds of human waiting time. Warm starts (reusing a live container) execute in milliseconds. Without understanding this, you'll misattribute slowness to query logic rather than infrastructure, and overprovision concurrent capacity unnecessarily.

When serverless is your query engine (e.g., AWS Athena on Lambda, BigQuery with on-demand slots, or custom Spark jobs on Fargate), cold starts become a scheduling problem: run your heaviest queries during warm windows, batch similar jobs together, or use provisioned capacity to eliminate the penalty entirely.

## Practice

**Problem:** A daily dashboard queries `job_postings_fact` at 6 AM to show top-paying remote roles by title. The first query runs in 12 seconds; identical queries 30 seconds later run in 2 seconds. You need to understand the cost of this delay.

```sql
-- First query (cold start ~10s overhead):
SELECT 
  job_title_short,
  COUNT(*) as count,
  ROUND(AVG(salary_year_avg), 0) as avg_salary
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY
GROUP BY job_title_short
ORDER BY avg_salary DESC
LIMIT 10;

-- Solution: Run a warm-up query first to initialize the compute pool
-- This executes before the user-facing query and absorbs the cold start penalty.
SELECT COUNT(*) FROM job_postings_fact LIMIT 1;

-- Then run the actual query (now warm, executes in ~2s):
SELECT 
  job_title_short,
  COUNT(*) as count,
  ROUND(AVG(salary_year_avg), 0) as avg_salary
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY
GROUP BY job_title_short
ORDER BY avg_salary DESC
LIMIT 10;
```

## Notes

- **Cold starts are environment-specific:** Lambda, Fargate, and BigQuery slots each have different penalty profiles. Always profile your actual platform; don't assume.
- **Concurrency multiplies the cost:** If you parallelize 20 queries across idle workers, you pay cold start 20 times. Use connection pooling and batch jobs when possible.
- **Provisioned capacity trades $ for predictability:** Reserved slots or provisioned concurrency eliminate cold starts but increase baseline costs. Right-size based on query SLA, not peak demand.
- **Memory ≠ performance here:** Larger function memory can reduce cold start slightly (faster CPU during init), but it's a 10–20% gain, not a silver bullet.
- **Adjacent topics:** query result caching (avoid re-running entirely), connection pooling (reuse warm clients), and slot reservation policies (BigQuery, Redshift Spectrum). Revisit when scaling to 100+ concurrent users.
