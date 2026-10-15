---
date: 2026-10-15
phase: cloud
topic: Databricks clusters: all-purpose vs job clusters
---

# Databricks clusters: all-purpose vs job clusters

*Cloud platforms and storage*

## Concept

**All-purpose clusters** remain running between jobs, charged per DBU (Databricks Unit) per hour even during idle time. They're designed for interactive development, ad-hoc queries, and collaboration where latency matters. **Job clusters** spin up on-demand, run a single job, then terminate, so you pay only for active compute time. Job clusters cost less for defined, repeatable workloads because there's no idle tax.

The choice directly impacts your cloud bill and query latency. An all-purpose cluster lets you iterate quickly during development but wastes money if left running overnight. A job cluster adds 3–5 minutes of startup overhead but eliminates idle charges for nightly batch jobs that run once and finish. If you're troubleshooting "why was my query slow," check whether a job cluster was still spinning up or whether your all-purpose cluster was undersized and competing for shared pool resources.

Without understanding this distinction, teams accidentally run low-volume nightly jobs on all-purpose clusters (paying 24/7 for 1 hour of work) or try to run heavy analytical work on minimally-sized job clusters that lack enough workers to process data in parallel, creating performance bottlenecks.

## Practice

**Problem:** You've been tasked to run a nightly report that counts job postings by title and location, filtered to remote jobs posted in the last 30 days. This job runs for ~5 minutes and completes by 6 AM daily. Currently it runs on a shared all-purpose cluster that your team uses for ad-hoc queries. Calculate rough savings by moving it to a job cluster, and write the SQL.

```sql
SELECT 
  job_title_short,
  job_location,
  COUNT(*) as posting_count,
  ROUND(AVG(salary_year_avg), 2) as avg_salary
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY
GROUP BY job_title_short, job_location
ORDER BY posting_count DESC;
```

**Savings estimate:** All-purpose cluster at 8 DBU/hr × $0.40/DBU costs ~$3.20/hour or ~$77/month in idle charges alone. A job cluster with 2-minute startup + 5-minute query = 7 minutes = ~$0.02/run × 30 days = ~$0.60/month.

## Notes

- **Cluster sizing matters as much as type**: An undersized job cluster with 2 workers will run slow queries despite low cost; an oversized all-purpose cluster wastes money on idle capacity. Match worker count to data volume and parallelism.
- **Startup overhead is real**: Job clusters add 3–5 minutes per run; avoid them for sub-minute queries or interactive exploration. Use all-purpose for development, switch to job clusters only after workload is finalized.
- **Instance pools reduce cold-start time**: Pre-warming a pool of instances can cut job cluster startup from 5 minutes to 30 seconds, bridging the gap for latency-sensitive scheduled jobs.
- **Cluster autoscaling applies to both**: Don't confuse termination with autoscaling. All-purpose clusters can autoscale down to save money during idle periods, but still charge minimum DBUs; job clusters scale within a single run and terminate when complete.
- **Adjacent: Databricks SQL Warehouses** offer a third option—serverless, managed compute for BI and SQL-only workloads. Review when your job is read-heavy and doesn't require Spark or PySpark.
