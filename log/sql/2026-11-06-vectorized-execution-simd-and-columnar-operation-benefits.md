---
date: 2026-11-06
phase: sql
topic: Vectorized execution: SIMD and columnar operation benefits
---

# Vectorized execution: SIMD and columnar operation benefits

*SQL for analytics and engineering*

## Concept

Vectorized execution and columnar storage allow databases to process multiple rows in a single CPU instruction (SIMD) and avoid materializing entire row objects. Instead of iterating through one row at a time, modern analytics engines load a column (or column chunk) into CPU cache, apply a predicate or transformation to all values simultaneously, then move to the next operation. This is why columnar databases like Parquet, DuckDB, and Snowflake's native storage outperform row-oriented systems for analytical queries—the CPU's vector registers can compare or sum 8–16 values per clock cycle rather than one.

Row-oriented storage (traditional OLTP databases) keeps all columns of a single row together in memory, which is efficient for transactional lookups ("get all fields for user_id = 123") but wastes cache and bandwidth during aggregations ("sum salary across 1M rows"). Without columnar execution, you fetch salary, job_title, location, and dozens of other fields you don't need, polluting your cache.

The performance difference becomes stark at scale: a columnar scan with a simple predicate (e.g., `WHERE salary_year_avg > 100000`) processes only the salary column and a bitmap of matching rows, completing in milliseconds. The same query on row storage reads the entire table into memory, processing irrelevant columns. Query planners exploit this by pushing predicates and projections down to the scan layer, avoiding materialization.

## Practice

**Problem:** You need to count how many remote-eligible jobs posted in the last 90 days have a salary above $120k. The naive approach materializes every job row; write a query that leverages columnar pruning and vectorized filtering to minimize memory and CPU work.

```sql
SELECT COUNT(*) AS high_paying_remote_jobs
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND salary_year_avg > 120000
  AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days';
```

**Why this works:** A columnar engine reads only three columns (`job_work_from_home`, `salary_year_avg`, `job_posted_date`); a smart planner applies all three predicates at scan time using SIMD comparisons and produces only the count, never materializing the full row or intermediate results. Row storage would fetch all columns and all rows first, then filter—far slower.

## Notes

- **Predicate pushdown is critical:** Always place `WHERE` conditions early and use specific column comparisons (avoid `SELECT *` in subqueries). Databases can only vectorize what they see at scan time.
- **Avoid row constructors and scalar functions in WHERE:** Expressions like `WHERE CAST(salary_year_avg AS VARCHAR) LIKE '%000'` break vectorization; use native types and vector-friendly operations.
- **Materialization kills performance:** Intermediate CTEs or subqueries that force row materialization defeat columnar benefits; use window functions and set operations instead when possible.
- **Connection to query plans:** Always inspect `EXPLAIN` output for "Scan" nodes with filter pushdown (`Filter: salary > 120000 [vectorized]` vs. a separate Filter node above Scan). This shows whether your DB optimized correctly.
- **Revisit: partitioning and Bloom filters** – these complement columnar execution by skipping entire files/segments before any SIMD work begins (partition pruning).
