---
date: 2026-10-14
phase: cloud
topic: Databricks SQL warehouses: serverless analytics compute
---

# Databricks SQL warehouses: serverless analytics compute

*Cloud platforms and storage*

## Concept

Databricks SQL warehouses are managed compute clusters optimized for analytical queries on cloud storage (Delta Lake, data lakes). Unlike traditional data warehouses with fixed capacity, serverless SQL warehouses auto-scale based on query load and pause during idle periods—you pay per DBU (Databricks Unit) consumed, not per hour. This model matters when you run unpredictable workloads: ad hoc reporting, exploratory queries, or bursty analytical jobs where provisioning a fixed cluster would be wasteful.

Without understanding warehouse sizing and query patterns, you'll either overpay (keeping clusters warm for occasional queries) or underpay and hit performance walls (undersized clusters choking on joins over large tables). The key insight is that query slowness often stems not from warehouse size alone, but from unoptimized data layout—missing statistics, unsorted data, or inefficient predicates that force full table scans even on a large warehouse.

Serverless removes capacity planning overhead but exposes cost visibility: a single poorly written query can explode your bill if it scans terabytes unnecessarily. You need to monitor query execution plans, understand partition pruning, and use EXPLAIN to spot where the planner is making expensive decisions.

## Practice

**Problem:** Marketing wants a report of high-paying remote jobs posted in the last 90 days, grouped by title. The query runs in 45 seconds on a large warehouse but costs $8 per run. How do you identify the bottleneck and optimize cost?

```sql
-- Original slow query
SELECT 
  job_title_short,
  COUNT(*) as job_count,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_work_from_home = true
  AND salary_year_avg > 100000
  AND job_posted_date >= CURRENT_DATE() - INTERVAL 90 DAY
GROUP BY job_title_short
ORDER BY avg_salary DESC;

-- Check execution plan first
EXPLAIN EXTENDED
SELECT job_title_short, COUNT(*), AVG(salary_year_avg)
FROM job_postings_fact
WHERE job_work_from_home = true
  AND salary_year_avg > 100000
  AND job_posted_date >= CURRENT_DATE() - INTERVAL 90 DAY
GROUP BY job_title_short;

-- Optimized: add Z-order clustering on frequently filtered columns
OPTIMIZE job_postings_fact
CLUSTER BY job_posted_date, job_work_from_home;

-- Gather statistics to help planner
ANALYZE TABLE job_postings_fact COMPUTE STATISTICS;

-- Re-run original query (now scans ~5% of data instead of 100%)
```

## Notes

- **Query plans lie by omission:** `EXPLAIN` shows logical operators, but `EXPLAIN EXTENDED` or the Databricks UI's "Query Profile" reveals actual data scanned; use the Profile tab to spot full table scans and skewed partitions.
- **Serverless billing trap:** You're charged per DBU regardless of warehouse size; a tiny warehouse running a bad query costs the same in absolute dollars as a large warehouse—it just takes longer. Optimize queries *before* scaling up.
- **Partition pruning is everything:** If `job_posted_date` is not a partition or Z-order column, the warehouse scans all 10 years of history even with a `WHERE job_posted_date >= ...` filter; check Delta table metadata with `DESCRIBE DETAIL job_postings_fact`.
- **Serverless vs. provisioned trade-off:** Serverless excels for variable workloads (saves money on idle time); if you have steady, predictable analytical load, provisioned warehouses may be cheaper despite lack of auto-pause.
- **Adjacent topic—cost control:** Set warehouse timeout policies, use query result caching (Databricks caches identical queries for 24h), and partition aggressively on date/region columns to ensure predicate pushdown works as expected.
