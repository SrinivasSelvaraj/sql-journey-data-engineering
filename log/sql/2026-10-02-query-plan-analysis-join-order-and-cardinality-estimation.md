---
date: 2026-10-02
phase: sql
topic: Query plan analysis: join order and cardinality estimation
---

# Query plan analysis: join order and cardinality estimation

*SQL for analytics and engineering*

## Concept

Query plan analysis reveals *how* a database executes your SQL—specifically, which tables it scans first, how it joins them, and whether it uses indexes. Join order and cardinality estimation are the two pillars: join order determines the sequence and filter application (early filtering on smaller result sets is cheaper), while cardinality estimation predicts row counts at each step. Without accurate cardinality, the optimizer might choose a nested-loop join when a hash join would be 100× faster, or scan a table full instead of using an index.

The optimizer makes these decisions based on table statistics (row counts, column value distributions, NULL counts). Stale or missing statistics cause poor cardinality estimates, leading to suboptimal plans. In production, a query that runs in 2 seconds with correct statistics might take 30 seconds with outdated ones—not because the data changed, but because the optimizer made wrong assumptions about intermediate result sizes.

Analyzing a plan teaches you to read EXPLAIN output, spot sequential scans on large tables, identify missing indexes, and rewrite queries to give the optimizer better information (e.g., adding predicates earlier, using CTEs to bound result sets, or restructuring joins to filter aggressively).

## Practice

**Problem:** Write a query to find all remote job postings from the last 90 days with average salary above $120k, joined with a second table to count applications per posting. Explain why join order matters.

```sql
-- Assume we also have: applications_fact(application_id, job_id, application_date)

-- GOOD: Filter early before the join
SELECT 
  j.job_id,
  j.job_title_short,
  j.salary_year_avg,
  COUNT(a.application_id) AS app_count
FROM job_postings_fact j
LEFT JOIN applications_fact a
  ON j.job_id = a.job_id
WHERE j.job_work_from_home = TRUE
  AND j.salary_year_avg > 120000
  AND j.job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY j.job_id, j.job_title_short, j.salary_year_avg
ORDER BY app_count DESC;

-- EXPLAIN ANALYZE output should show:
-- 1. Filter on job_postings_fact (work_from_home, salary, date)
-- 2. Hash join with applications_fact using job_id
-- This limits the left table size *before* joining, reducing rows processed
```

The optimizer should filter `job_postings_fact` first (ideally via index on `job_posted_date` + filter on `job_work_from_home` and `salary_year_avg`), reducing cardinality from millions to thousands, *then* join. If you wrote it with the filter in a `HAVING` clause instead, the optimizer might join first (millions × millions rows) and filter after—catastrophically slower.

## Notes

- **Cardinality estimation fails on:** multi-column predicates (optimizer assumes independence), OR conditions, complex expressions, and rapidly changing data. Always ANALYZE tables after bulk loads.
- **Index selection depends on plan:** a query using a nested-loop join may need an index on the inner table's join column; a hash join doesn't use indexes for the join itself but benefits from index scans on filter predicates.
- **Join order ties to selectivity:** join the most selective table (fewest rows after filters) first, then progressively larger sets. This is why early WHERE clauses matter even if they seem redundant.
- **EXPLAIN ANALYZE vs. EXPLAIN:** EXPLAIN shows the *plan*; EXPLAIN ANALYZE actually runs the query and shows *real* row counts. Always use ANALYZE in dev to spot where estimates diverged from reality.
- **Adjacent topics:** statistics and VACUUM, index design, cost-based vs. rule-based optimization, temporal queries (date range filters), and partition pruning in large tables.
