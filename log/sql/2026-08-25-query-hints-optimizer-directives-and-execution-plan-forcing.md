---
date: 2026-08-25
phase: sql
topic: Query hints: optimizer directives and execution plan forcing
---

# Query hints: optimizer directives and execution plan forcing

*SQL for analytics and engineering*

## Concept

Query hints are directives you embed in SQL to override the query optimizer's default execution plan decisions. The optimizer uses statistics and cost models to choose join orders, index usage, and access methods, but these choices sometimes miss domain knowledge you possess—like "this small lookup table should always be broadcast" or "this join should use a hash algorithm, not a nested loop." Without hints, you might get full table scans on indexed columns, terrible join orders on large fact tables, or repeated computation of expensive CTEs. Hints matter most in production analytics when a query runs fine on test data but becomes a resource killer on 100M rows, or when you know the optimizer's cardinality estimates are wildly wrong.

Different systems use different syntax. PostgreSQL uses comments or `SET` statements; SQL Server uses `OPTION` clauses; Presto/Trino use comments like `/*+ hint */`; BigQuery avoids hints and instead relies on explicit joins and `APPROX_QUANTILES`. The key is *forcing* a plan when you have evidence the optimizer will choose poorly—but use sparingly, because hints lock you into a strategy that may degrade as data volume or distribution changes. Good hint usage requires understanding actual execution plans (via EXPLAIN or query profiles) and knowing when the optimizer is genuinely fooled.

## Practice

**Problem:** You're querying a job postings data warehouse. You need to find the top 10 highest-paid remote jobs by location. The naive query does a full table scan and sorts millions of rows, but you know a covering index exists on `(job_work_from_home, salary_year_avg DESC, job_location)`. Force the optimizer to use that index and avoid the sort.

```sql
-- SQL Server syntax with index hint
SELECT TOP 10
    job_id,
    job_title_short,
    salary_year_avg,
    job_location
FROM job_postings_fact WITH (INDEX(idx_remote_salary_location))
WHERE job_work_from_home = 1
ORDER BY salary_year_avg DESC, job_location;

-- PostgreSQL syntax using index hint comment
SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_location
FROM job_postings_fact
WHERE job_work_from_home = true
ORDER BY salary_year_avg DESC
LIMIT 10;
-- Execute: SET enable_seqscan = off; before query to force index usage

-- BigQuery: no direct hint, but force index-friendly execution
SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_location
FROM `project.dataset.job_postings_fact`
WHERE job_work_from_home = true
ORDER BY salary_year_avg DESC
LIMIT 10;
-- BigQuery optimizes automatically; if slow, verify table stats are fresh with ANALYZE TABLE
```

## Notes

- **Overuse trap:** Hints lock you into a plan. When data distribution shifts (e.g., remote jobs drop from 40% to 5% of postings), a hinted nested-loop join becomes catastrophic. Always revisit hints quarterly.
- **EXPLAIN first:** Never write a hint without running `EXPLAIN` or looking at the query profile. Guessing wrong is worse than trusting the optimizer.
- **Cardinality estimation is the root cause:** Hints usually mask bad statistics or outdated table metadata. Run `ANALYZE` or `VACUUM` first; often the optimizer will fix itself.
- **Join hints vs. access hints:** Join hints (e.g., `HASH JOIN`) control algorithm; access hints (e.g., `INDEX`) control table access. Use join hints when you know the optimizer will pick nested loop on a 1M × 100M cross-join.
- **Connects to:** query profiling, index strategy, materialized views (alternative to hints), and cardinality estimation bugs. Hints are a last resort before redesigning your schema or materializing intermediate results.
