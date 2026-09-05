---
date: 2026-09-05
phase: cloud
topic: FinOps maturity: crawl-walk-run for cost culture
---

# FinOps maturity: crawl-walk-run for cost culture

*Cloud platforms and storage*

## Concept

FinOps maturity in the crawl-walk-run framework starts with foundational cost visibility: understanding what you're paying for on cloud platforms and why queries perform poorly. Without this visibility, teams waste resources on inefficient queries, oversized compute, and redundant storage without visibility into the cost impact. This phase is critical because cost and performance are inseparable—a slow query isn't just a latency problem; it's a direct drain on your cloud bill through compute hours and data scanned.

The core practice is tagging resources, monitoring query execution plans, and correlating slow queries to their cost drivers. On cloud platforms like BigQuery or Snowflake, you need to know: How many bytes did this query scan? How much compute time did it consume? What's the unit cost model? Without this baseline, optimization is guesswork. Teams at this stage move from reactive "why is the bill so high?" to proactive "which queries are expensive and why?"

This forms the foundation for the walk and run phases, where you'll prioritize optimization efforts and build cost allocation models. Skipping this phase leads to teams optimizing the wrong things or burning out on firefighting inefficiency without understanding root causes.

## Practice

**Problem:** Your analytics team runs daily aggregations on job postings to track hiring trends by location and salary. The queries are slow (taking 15 minutes) and you suspect the cost is high, but you don't know which step is the culprit or how much data is actually being scanned.

```sql
-- Add query instrumentation to understand cost drivers
-- Step 1: Check raw data size and scans
SELECT
  COUNT(*) as total_records,
  APPROX_QUANTILES(BYTE_LENGTH(CAST(job_title_short AS STRING)), 100)[OFFSET(50)] as median_title_size
FROM job_postings_fact;

-- Step 2: Slow aggregation with execution insights
-- Run with EXPLAIN to see execution plan before full execution
EXPLAIN
SELECT
  job_location,
  EXTRACT(YEAR FROM job_posted_date) as posting_year,
  COUNT(*) as posting_count,
  ROUND(AVG(salary_year_avg), 2) as avg_salary
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
GROUP BY job_location, posting_year
ORDER BY posting_count DESC;

-- Step 3: Optimized version with partition pruning
-- Push filtering down, avoid full table scans
SELECT
  job_location,
  EXTRACT(YEAR FROM job_posted_date) as posting_year,
  COUNT(*) as posting_count,
  ROUND(AVG(salary_year_avg), 2) as avg_salary
FROM job_postings_fact
WHERE job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
  AND job_work_from_home = TRUE
GROUP BY job_location, posting_year
ORDER BY posting_count DESC;
```

Run both queries and compare bytes scanned in the job details panel—the optimized version should show significantly lower bytes processed by filtering earlier in the pipeline.

## Notes

- **Missing cost attribution**: Many teams track total cloud spend but don't connect it to specific queries or users. Use cloud cost tags (labels in GCP, tags in AWS) on every workload to enable cost-per-department or cost-per-project analysis.

- **Confusing slow ≠ expensive**: A 2-second query scanning 100 GB is cheaper than a 10-second query scanning 1 GB on some platforms. Always inspect *bytes scanned* and *compute time separately*, not just elapsed time.

- **Partition and clustering are your friends**: Most cost wins in crawl phase come from adding date partitioning or clustering columns to avoid full table scans. This directly reduces both latency and cloud costs.

- **Adjacent topics**: Cost monitoring connects directly to data modeling (normalization vs. denormalization affects scan size), indexing strategies, and query caching patterns. Revisit these as you move to walk phase.

- **Common trap**: Setting up cost alerts but no cost *analysis*. Alerts tell you spend spiked; analysis tells you *why* and what to fix. This phase is about building the "why" muscle before you automate responses.
