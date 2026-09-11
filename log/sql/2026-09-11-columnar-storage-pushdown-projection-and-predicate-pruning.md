---
date: 2026-09-11
phase: sql
topic: Columnar storage pushdown: projection and predicate pruning
---

# Columnar storage pushdown: projection and predicate pruning

*SQL for analytics and engineering*

## Concept

Columnar storage (Parquet, ORC) stores data by column rather than by row, enabling two critical optimizations: **projection pushdown** skips reading unused columns entirely, and **predicate pushdown** filters rows at storage read time before loading into memory. Together, they reduce I/O and CPU dramatically—a query selecting 3 of 50 columns and filtering to 1% of rows may read only ~0.03% of the original data instead of 100%.

Without pushdown, the query engine reads entire row groups or files, then discards unwanted columns and rows in-memory. With pushdown, filters execute in the storage layer (Parquet metadata, Bloom filters, min-max statistics) before data reaches the compute engine. This matters most for analytics on wide tables with selective queries—common in data warehouses and data lakes.

Pushdown is *transparent* when you write standard SQL; optimizers in engines like Presto, Spark, and DuckDB apply it automatically. However, poor query design (complex expressions in WHERE clauses, derived tables that prevent pushdown) can disable it. Understanding which predicates push down teaches you to write queries that stay performant as tables grow.

## Practice

**Problem:** You query `job_postings_fact` for remote software engineer roles posted in the last 30 days, but you only need job ID and title. The table has 50M rows across 15 columns. Without pushdown, the engine reads all 15 columns for all rows; with it, only 2 columns and ~2% of rows load.

Write a query that enables both projection and predicate pushdown:

```sql
SELECT
  job_id,
  job_title_short
FROM job_postings_fact
WHERE
  job_work_from_home = true
  AND job_title_short LIKE '%Software Engineer%'
  AND job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY
ORDER BY job_posted_date DESC;
```

**Why this works:**  
- SELECT lists only 2 columns (projection pushdown).  
- WHERE uses simple, column-native predicates (boolean comparison, string pattern, date range) that execute in the storage layer before materialization.  
- No derived tables, CASE expressions, or UDFs hide the predicates from the optimizer.

## Notes

- **Avoid expressions that block pushdown:** `WHERE YEAR(job_posted_date) = 2024` prevents date pruning; use range predicates `job_posted_date >= '2024-01-01'` instead. Similarly, `WHERE salary_year_avg * 1.1 > 100000` disables pushdown on `salary_year_avg`.

- **Derived tables and CTEs hide predicates:** A CTE that selects all 50 columns forces the engine to materialize them; push the filter *inside* the CTE or reference the base table directly in WHERE.

- **Parquet metadata enables row-group skipping:** Min-max statistics and Bloom filters on Parquet files are checked before reading; overly broad predicates (e.g., date ranges spanning months) reduce skipping efficiency.

- **Column order and partitioning interact:** Tables partitioned by date allow partition-level pruning *before* Parquet statistics are consulted—nest time-range filters early in WHERE.

- **Connects to:** query plan inspection (EXPLAIN to verify pushdown actually happens), partitioning strategy, and stats-based optimization; revisit after learning Spark DAG visualization or Presto EXPLAIN ANALYZE.
