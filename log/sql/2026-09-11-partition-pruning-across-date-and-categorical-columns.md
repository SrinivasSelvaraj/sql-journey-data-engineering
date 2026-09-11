---
date: 2026-09-11
phase: sql
topic: Partition pruning across date and categorical columns
---

# Partition pruning across date and categorical columns

*SQL for analytics and engineering*

## Concept

Partition pruning is a query optimization technique where the query engine eliminates entire partitions of data without scanning them, based on predicates in your WHERE clause. When a table is partitioned by date (common in data warehouses) or categorical columns, filtering on those columns allows the engine to skip whole file sets or directories. Without partition pruning, you scan unnecessary data, increasing I/O, compute time, and cost—especially critical in cloud warehouses (Redshift, BigQuery, Snowflake) where you're charged per GB scanned.

Partition pruning works because partitioned tables physically organize data by the partition key (e.g., separate files/directories for each date or region). When your WHERE clause filters on that partition column directly (not derived, not in a subquery), the optimizer recognizes it can skip partitions entirely. The pruning fails silently if you apply functions to the partition column, compare it against another table, or use dynamic values the optimizer can't evaluate at plan time.

This matters most in large fact tables (billions of rows) queried repeatedly; scanning even 10% of unnecessary partitions can double query time and triple costs. It's especially critical in batch analytics and reporting where similar date ranges are queried daily, and in multi-tenant systems where filtering by tenant ID (a categorical partition) is required for correctness and performance.

## Practice

**Problem:** You have a job postings fact table partitioned by `job_posted_date` (DATE). Write a query to find the average salary for remote data engineering jobs posted in the last 30 days. The query should allow the engine to prune partitions outside that date range.

```sql
SELECT 
  job_title_short,
  COUNT(*) as job_count,
  ROUND(AVG(salary_year_avg), 2) as avg_salary
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_title_short = 'Data Engineer'
  AND job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY
GROUP BY job_title_short
ORDER BY avg_salary DESC;
```

**Why this works:** The predicate `job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY` is applied directly to the partition column with a constant expression the optimizer can evaluate. The engine identifies which date partitions fall within the last 30 days and skips all older partitions entirely. The boolean and string filters run *within* the selected partitions, not before pruning.

## Notes

- **Anti-pattern:** `WHERE YEAR(job_posted_date) = 2024` prevents pruning because the function obscures the partition column; instead use range predicates like `job_posted_date >= '2024-01-01'`.
- **Multi-column partitioning:** If partitioned by both `job_posted_date` and `job_location`, filter both directly for maximum pruning; filtering only one still prunes by that dimension, but the other partitions still scan.
- **Dynamic values:** Subqueries like `WHERE job_posted_date >= (SELECT MAX(date) - 30 FROM metadata_table)` may not prune if the optimizer can't resolve the subquery at plan time; pre-compute the date constant when possible.
- **Verify with EXPLAIN:** Always run `EXPLAIN` or `EXPLAIN ANALYZE` to confirm partition elimination is happening; look for "Partitions scanned" or similar metrics in the query plan.
- **Adjacent topics:** Understand clustering (secondary sort order for non-partition columns), Z-order curves (multi-dimensional pruning), and table statistics; these work together to make full-scan avoidance effective.
