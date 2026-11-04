---
date: 2026-11-04
phase: sql
topic: Query plan explain output: nodes, costs and cardinality estimates
---

# Query plan explain output: nodes, costs and cardinality estimates

*SQL for analytics and engineering*

## Concept

An EXPLAIN (or EXPLAIN PLAN) output reveals how a database engine will execute—or has executed—your query. It shows a tree of nodes (operations like sequential scans, index lookups, joins, aggregations) with associated costs and cardinality estimates. **Cost** is a relative measure of resource consumption (CPU, I/O); **cardinality** is the predicted number of rows each operation will produce. Understanding this output is critical because a query that *feels* correct can be dramatically slow if the optimizer makes bad choices: using a full table scan instead of an index, choosing a nested-loop join over a hash join, or pushing a filter too late in the plan.

Without reading explain output, you're blind to why a query performs poorly. A query returning 10 rows might take 30 seconds if the planner estimated 1 billion rows and chose a terrible join strategy. Cardinality estimates drive the optimizer's decisions; if estimates are wildly wrong (due to stale statistics, missing column correlations, or skewed data), the optimizer picks a suboptimal plan. Learning to spot these mismatches—and rewrite queries to guide the planner—is essential for interview performance and real production work.

## Practice

**Problem:** Write a query to find the average salary for remote data engineering jobs posted in the last 90 days, grouped by job title. Run EXPLAIN to identify whether the filter on `job_posted_date` is applied early, and verify the cardinality estimate for remote jobs is reasonable.

```sql
EXPLAIN (FORMAT JSON)
SELECT 
  job_title_short,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary,
  COUNT(*) AS job_count
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
  AND salary_year_avg IS NOT NULL
GROUP BY job_title_short
HAVING COUNT(*) >= 5
ORDER BY avg_salary DESC;
```

Run this with `EXPLAIN ANALYZE` to see actual vs. estimated rows. Look for: (1) Is the date filter applied as a **Filter** node early (ideally in a sequential scan or index scan), before the aggregation? (2) Does the cardinality estimate for rows after filtering match reality? (3) Is there an index on `(job_work_from_home, job_posted_date)` that could speed up filtering?

## Notes

- **Common mistake:** Ignoring the Filter cost—filters applied *after* a join or aggregation waste CPU on rows that should never have been processed. Always push predicates down.
- **Cardinality mismatch red flag:** If EXPLAIN shows Rows: 1000 but EXPLAIN ANALYZE shows actual 50000, statistics are stale; consider `ANALYZE table_name` to refresh.
- **Index leverage:** Look for "Index Scan" or "Bitmap Index Scan" in output; "Sequential Scan" + high cost suggests a missing or unused index on frequently filtered columns.
- **Join strategy:** Hash joins scale better than nested loops for large datasets; if you see nested loop on millions of rows, rewrite the join condition or add an index.
- **Adjacent skill:** Learn to use `COST` thresholds (e.g., `SET random_page_cost = 1` in PostgreSQL) and understand how your database weights sequential vs. random I/O when choosing plans.
