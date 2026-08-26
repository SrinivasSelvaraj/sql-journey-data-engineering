---
date: 2026-08-26
phase: sql
topic: Partitioning pruning in where clause effectiveness
---

# Partitioning pruning in where clause effectiveness

*SQL for analytics and engineering*

## Concept

Partition pruning occurs when a query optimizer eliminates entire partitions of data based on predicates in the WHERE clause, without scanning them. In partitioned tables (commonly partitioned by date, region, or category), a well-written WHERE clause lets the engine skip irrelevant partitions entirely, reducing I/O and compute dramatically. For example, if a table is partitioned by `job_posted_date` into monthly chunks, filtering `WHERE job_posted_date >= '2024-01-01'` allows the engine to skip all 2023 partitions.

Without effective partition pruning, queries scan all partitions regardless of the WHERE clause, treating the table as unpartitioned. This happens when: predicates use functions that obscure partition columns (`WHERE YEAR(job_posted_date) = 2024` instead of date ranges), predicates are buried in OR conditions with non-partition columns, or the column type mismatches the partition key (string vs. date). The performance penalty scales with table size—a 10TB partitioned table scanned completely defeats the partition strategy.

Partition pruning is most critical in OLAP systems (data warehouses, analytics DBs) where tables are massive and partitioned intentionally for performance. It's less relevant in small OLTP tables or non-partitioned environments, but the *principle*—letting filters work at the access layer—applies universally to index selection and query optimization.

## Practice

**Problem:** Write a query to find the average salary for remote software engineering jobs posted in the last 90 days. The `job_postings_fact` table is partitioned by `job_posted_date` (daily partitions). Ensure partition pruning is effective.

```sql
SELECT 
  AVG(salary_year_avg) AS avg_salary
FROM job_postings_fact
WHERE 
  job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
  AND job_posted_date < CURRENT_DATE
  AND job_work_from_home = TRUE
  AND job_title_short = 'Software Engineer'
  AND salary_year_avg IS NOT NULL;
```

**Why this works:** The date range uses direct column comparison (`>=` and `<`) without functions, allowing the optimizer to identify and scan only the last 90 days of partitions. The non-partition predicates (`job_work_from_home`, `job_title_short`) are applied *after* partition pruning narrows the scan scope.

## Notes

- **Anti-pattern: Functions obscure partition columns.** `WHERE YEAR(job_posted_date) = 2024` prevents pruning; use `WHERE job_posted_date >= '2024-01-01' AND job_posted_date < '2025-01-01'` instead.
- **OR conditions with non-partition columns kill pruning.** `WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days' OR job_location = 'Remote'` must scan all partitions because the OR branch doesn't reference the partition key.
- **Type coercion matters.** If `job_posted_date` is DATE but you filter `WHERE job_posted_date >= '2024-01-01'::TEXT`, the implicit cast may prevent pruning; keep types aligned.
- **Connects to:** index selectivity (similar optimization principle at a different layer), query plan reading (EXPLAIN output shows "Partition Pruning: ON" or partition counts), and materialized views (pre-aggregated partitions sidestep the problem entirely).
- **Revisit:** Check your engine's documentation (Redshift, BigQuery, Snowflake, Postgres) for partition pruning syntax and guarantees; behavior varies.
