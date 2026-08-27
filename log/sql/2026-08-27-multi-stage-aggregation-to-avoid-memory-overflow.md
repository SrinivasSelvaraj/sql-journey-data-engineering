---
date: 2026-08-27
phase: sql
topic: Multi-stage aggregation to avoid memory overflow
---

# Multi-stage aggregation to avoid memory overflow

*SQL for analytics and engineering*

## Concept

Multi-stage aggregation breaks a single large aggregation into smaller, sequential stages to reduce memory consumption and improve query performance. Instead of grouping millions of rows by many dimensions at once, you aggregate to intermediate granularity first, then aggregate the results. This is critical when working with high-cardinality dimensions (many unique values per group) or large fact tables where a naive GROUP BY would materialize an enormous intermediate result set.

Without multi-stage aggregation, the query engine must hold all grouped rows in memory before producing output. For example, grouping 50M job postings by (job_title, job_location, salary_band) might create millions of groups that exceed available RAM, causing spills to disk or out-of-memory errors. Multi-stage aggregation reduces peak memory by materializing only necessary intermediate results and re-aggregating them, often improving runtime by 10–100x for large datasets.

The technique is especially important in interview settings because it demonstrates understanding of query execution fundamentals and memory constraints—knowledge that separates junior from senior engineers. It also signals you can reason about cardinality, selectivity, and execution plans under pressure.

## Practice

**Problem:** Find the average salary by job title and work-from-home status across all job postings, but the dataset is large enough that a direct GROUP BY causes memory pressure.

```sql
-- Stage 1: Aggregate to intermediate granularity (job_id + dimensions)
WITH stage1 AS (
  SELECT
    job_title_short,
    job_work_from_home,
    salary_year_avg
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
),

-- Stage 2: Aggregate intermediate results to final granularity
stage2 AS (
  SELECT
    job_title_short,
    job_work_from_home,
    COUNT(*) AS posting_count,
    SUM(salary_year_avg) AS total_salary,
    AVG(salary_year_avg) AS avg_salary
  FROM stage1
  GROUP BY job_title_short, job_work_from_home
)

SELECT * FROM stage2
ORDER BY avg_salary DESC;
```

In this example, Stage 1 filters and selects only necessary columns early, reducing the dataset's memory footprint before aggregation. Stage 2 then groups the smaller Stage 1 result. For very large tables, you could add intermediate stages (e.g., aggregate by location first, then by title+location, then by title+location+remote).

## Notes

- **Cardinality is key:** Multi-stage aggregation helps most when you have high-cardinality dimensions (e.g., 10K+ unique job titles). Low-cardinality cases (e.g., 2 remote statuses) don't benefit as much.
- **Watch for correctness:** Ensure each stage preserves the correct aggregation semantics. Summing counts and totals works; averaging averages does not (use SUM/COUNT instead).
- **Materialization trade-off:** CTEs and temporary tables can help, but writing to disk has its own cost; profile before assuming multi-stage is faster in your specific engine.
- **Query plan inspection:** Always check EXPLAIN output to confirm stages run sequentially and that early filters reduce cardinality as expected.
- **Related concepts:** Window functions, approximate aggregations (HyperLogLog), and approximate query processing (sampling) are complementary techniques for memory-constrained scenarios.
