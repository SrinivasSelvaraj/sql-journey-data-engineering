---
date: 2026-10-24
phase: sql
topic: EXPLAIN ANALYZE actual execution metrics
---

# EXPLAIN ANALYZE actual execution metrics

*SQL for analytics and engineering*

## Concept

`EXPLAIN ANALYZE` executes a query and returns both the query plan *and* actual runtime metrics—showing estimated vs. real row counts, actual execution time, and I/O statistics. Unlike bare `EXPLAIN`, which only shows the optimizer's guess, `EXPLAIN ANALYZE` reveals whether the planner made correct assumptions and where time actually gets spent. This matters because a plan that looks efficient on paper may perform poorly due to stale statistics, skewed data distribution, or index misuse.

Without running `EXPLAIN ANALYZE`, you optimize based on incomplete information. You might add an index that doesn't help, or miss that a sequential scan is actually faster than an index lookup for your data volume. In interviews, this tool demonstrates you understand the gap between theory and reality—that you won't ship a query just because it looks good in the plan.

When actual row counts deviate significantly from estimates, it signals stale table statistics (run `ANALYZE` on the table), missing or poor index design, or a WHERE clause the planner misjudges. High "Actual Total Time" on a node that shows low estimated cost is the smoking gun that forces you to reconsider your approach.

## Practice

**Problem:** A report queries job postings to find remote data engineering roles with salary > $120k, ordered by posting date. The query feels slow. Write a command to diagnose the issue and identify which step consumes the most time.

```sql
EXPLAIN ANALYZE
SELECT job_id, job_title_short, salary_year_avg, job_posted_date
FROM job_postings_fact
WHERE job_work_from_home = true
  AND job_title_short ILIKE '%Data Engineer%'
  AND salary_year_avg > 120000
ORDER BY job_posted_date DESC
LIMIT 50;
```

Read the output: if the planner estimated 500 rows but found 50,000, your WHERE clause selectivity is misunderstood—add stats or refactor. If the sort dominates execution time, consider a covering index on `(job_work_from_home, job_title_short, salary_year_avg, job_posted_date)` or partition by posting date.

## Notes

- **Plan vs. reality gap**: Estimated rows ÷ actual rows > 10× means stale stats—run `ANALYZE TABLE job_postings_fact;` then re-run `EXPLAIN ANALYZE`.
- **Memory and I/O**: Watch for "Buffers: shared hit/read/written" (PostgreSQL) or "Memory: X kB" (some systems)—disk reads are 1000× slower than cache hits.
- **Joins and nested loops**: When joining large tables, an estimated outer loop of 100 rows but actual 100,000 rows causes exponential slowdown; spot this early with `EXPLAIN ANALYZE` on the join plan.
- **Test data vs. production**: A query fast on a 1M-row dev table may crawl on 500M rows in production; always sanity-check plans on representative scale.
- **Adjacent skills**: Learn `VACUUM ANALYZE` (maintenance), index design trade-offs, and how to read "Filter" vs. "Index Cond" nodes to distinguish what filtering happens where.
