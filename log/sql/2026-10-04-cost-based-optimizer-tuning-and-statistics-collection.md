---
date: 2026-10-04
phase: sql
topic: Cost-based optimizer tuning and statistics collection
---

# Cost-based optimizer tuning and statistics collection

*SQL for analytics and engineering*

## Concept

A cost-based optimizer uses table and column statistics (row counts, cardinality, distribution, NULL ratios) to estimate query execution cost and choose the cheapest plan. Without accurate statistics, the optimizer makes poor decisions: it might choose a nested-loop join over a hash join, scan a large table instead of using an index, or execute subqueries in the wrong order. Statistics become critical when:

- Tables have skewed data (e.g., 90% of job postings are in one location)
- Join selectivity is non-obvious (e.g., matching job titles across two large tables)
- Filter predicates reduce rows unpredictably (e.g., `salary_year_avg > 150000` eliminates 5% or 95% depending on market)

Stale or missing statistics force the optimizer to use default assumptions—typically uniform distribution—which leads to wildly suboptimal plans. For analytics workloads with multi-table joins and aggregations, this is the difference between a 5-second query and a 5-minute hang.

## Practice

**Problem:** You have a query joining `job_postings_fact` to a `skills_required` table (millions of rows each). The planner is choosing a nested-loop join instead of a hash join, making the query slow. How do you diagnose and fix this?

```sql
-- First, check statistics freshness and cardinality
ANALYZE TABLE job_postings_fact;
ANALYZE TABLE skills_required;

-- Inspect the query plan before and after
EXPLAIN SELECT
  jp.job_title_short,
  COUNT(DISTINCT sr.skill_id) AS skill_count,
  AVG(jp.salary_year_avg) AS avg_salary
FROM job_postings_fact jp
INNER JOIN skills_required sr ON jp.job_id = sr.job_id
WHERE jp.job_posted_date >= '2024-01-01'
  AND jp.salary_year_avg > 120000
GROUP BY jp.job_title_short
ORDER BY skill_count DESC;

-- If still slow, gather column-level statistics on join keys
ANALYZE TABLE job_postings_fact COMPUTE STATISTICS FOR COLUMNS job_id;
ANALYZE TABLE skills_required COMPUTE STATISTICS FOR COLUMNS job_id;

-- Verify row count and distinct values
SELECT COUNT(*), COUNT(DISTINCT job_id) FROM job_postings_fact;
SELECT COUNT(*), COUNT(DISTINCT job_id) FROM skills_required;
```

After `ANALYZE`, the optimizer has cardinality estimates and can decide whether a hash join or nested loop is cheaper. If the nested loop persists, check for data skew or missing histogram statistics.

## Notes

- **Statistics decay over time:** batch jobs and incremental loads change row counts and distributions; refresh stats weekly or after major data changes, not just once.
- **Histogram buckets matter:** a column with 1M distinct values needs fine-grained histograms; default bucket counts (e.g., 100) may miss critical skew.
- **Join selectivity estimation is fragile:** if the optimizer doesn't know the correlation between two columns, it assumes independence and guesses wrong; explicit `EXPLAIN ANALYZE` output is your debugging tool.
- **Index hints vs. statistics:** forcing an index with a hint works short-term but masks the real problem; fix statistics first, then add hints only as a last resort.
- **Adjacent: table partitioning, adaptive query execution, runtime statistics collection** — modern engines (Spark, Presto) adapt mid-flight when optimizer estimates are wrong, but that's expensive; good statistics prevent it.
