---
date: 2026-10-02
phase: sql
topic: Partition pruning and predicate pushdown mechanics
---

# Partition pruning and predicate pushdown mechanics

*SQL for analytics and engineering*

## Concept

Partition pruning eliminates entire partitions from a scan based on filter conditions, while predicate pushdown moves filter logic as close as possible to the data source—both dramatically reduce I/O and CPU cost. When a table is partitioned by date (e.g., `job_posted_date`), a query filtering `WHERE job_posted_date >= '2024-01-01'` can skip scanning older partitions entirely rather than reading and discarding rows. Predicate pushdown ensures the WHERE clause is applied *during* the table scan, not after—so if you filter on `salary_year_avg > 100000`, the engine applies that test at read time, not on the full result set.

Without these optimizations, queries degrade catastrophically on large tables: a query that should read 1% of data ends up reading 100%, then filtering in-memory. This matters most in cloud data warehouses (Snowflake, BigQuery, Redshift) and distributed systems (Spark) where partition metadata is tracked separately and I/O is the dominant cost. Many junior engineers accidentally *disable* these optimizations by wrapping filter columns in functions (e.g., `WHERE YEAR(job_posted_date) = 2024`), applying transformations before filtering, or using expressions that the optimizer cannot translate into partition-level decisions.

## Practice

**Problem:** You have a fact table partitioned by `job_posted_date` (monthly partitions). Write a query that finds the average salary for remote software engineering jobs posted in the last 90 days. Ensure partition pruning and predicate pushdown work correctly.

```sql
SELECT 
  AVG(salary_year_avg) AS avg_salary,
  COUNT(*) AS job_count
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
  AND job_posted_date < CURRENT_DATE
  AND job_work_from_home = TRUE
  AND job_title_short ILIKE '%Software Engineer%'
;
```

**Why this works:**
- `job_posted_date` comparison uses a direct column reference (not a function), enabling the optimizer to prune partitions before scanning.
- All WHERE conditions are simple predicates that push down to the storage layer.
- Date bounds are explicit, not derived from functions like `YEAR()`.

**Anti-pattern to avoid:**
```sql
-- ❌ DISABLES partition pruning
WHERE YEAR(job_posted_date) = 2024
  AND EXTRACT(MONTH FROM job_posted_date) >= 10
;
```

## Notes

- **Function wrapping kills pruning:** Any function applied to a partition column (`YEAR()`, `DATE_TRUNC()`, `CAST()`) may prevent the optimizer from determining which partitions to skip. Use direct comparisons instead.
- **Filter order doesn't matter logically, but metadata helps:** Place partition column filters early in the WHERE clause for readability; the optimizer will reorder anyway, but humans benefit from seeing the structural filter first.
- **Predicate pushdown + joins:** When joining partitioned tables, push filters on the partitioned table *before* the join; filters on non-partitioned tables or join results cannot prune as effectively.
- **Cloud warehouse specifics:** Snowflake and BigQuery expose partition pruning statistics in EXPLAIN output; always inspect query plans to confirm pruning is happening (`bytes_scanned` should be small relative to table size).
- **Connects to:** query plan analysis (EXPLAIN), indexing strategy, columnar storage benefits, cost optimization in cloud warehouses.
