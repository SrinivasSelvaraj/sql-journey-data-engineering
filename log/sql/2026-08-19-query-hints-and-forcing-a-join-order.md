---
date: 2026-08-19
phase: sql
topic: Query hints and forcing a join order
---

# Query hints and forcing a join order

*SQL for analytics and engineering*

## Concept

Query hints are directives that instruct the query optimizer to follow a specific execution strategy, most commonly used to force a particular join order when the optimizer chooses a suboptimal plan. The optimizer relies on statistics (table sizes, index cardinality, data distribution) to estimate costs, but these statistics can be stale, incomplete, or misleading in edge cases—leading it to choose a plan that scans a large table first or performs expensive nested-loop joins when a hash join would be faster.

Forcing join order matters most when: (1) joining many tables where the optimizer must choose from factorial combinations of orderings, (2) filtering one table down to a tiny result set before joining to larger tables, or (3) the statistics are known to be wrong (e.g., a newly loaded table with no updated histograms). Without explicit hints, you may see query times jump from milliseconds to minutes as the optimizer makes a single wrong choice early in the plan.

Different databases support hints differently: PostgreSQL uses `/*+ <hint> */` comments or the `enable_*` parameters; MySQL uses `/*! /*+ hint */ */` syntax; SQL Server uses `OPTION (...)` clauses; Snowflake and BigQuery have limited hint support. The safest approach is to understand your database's hint syntax and know when to apply them—rarely by default, but deliberately when you've diagnosed a plan problem.

## Practice

**Problem:** You're querying job postings and need to find remote data engineering roles posted in the last 90 days with salary > $120k. You notice the query is slow because the optimizer is filtering `job_postings_fact` by salary first (scanning millions of rows), then checking the date and work-from-home columns. You want to force it to filter by the most selective condition (work-from-home = true, which is ~20% of rows) first.

```sql
-- PostgreSQL / standard SQL with hint
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_posted_date
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
  AND salary_year_avg > 120000
ORDER BY salary_year_avg DESC;

-- SQL Server (if join involved, force order with OPTION)
SELECT 
  jp.job_id,
  jp.job_title_short,
  jp.salary_year_avg
FROM job_postings_fact jp
INNER JOIN some_other_table sot ON jp.job_id = sot.job_id
WHERE jp.job_work_from_home = TRUE
  AND jp.job_posted_date >= CAST(GETDATE() - 90 AS DATE)
  AND jp.salary_year_avg > 120000
OPTION (LOOP JOIN);  -- or HASH JOIN, MERGE JOIN

-- PostgreSQL with enable_* GUC to force index usage
SET enable_seqscan = OFF;  -- disables sequential scans
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND salary_year_avg > 120000;
RESET enable_seqscan;
```

## Notes

- **Hints are a last resort, not first instinct**: misguided hints can lock a suboptimal plan in place even as data distribution changes. Always verify the hint solves a real problem (via `EXPLAIN ANALYZE`) before committing it.
- **Join order and cardinality reduction**: the most impactful hints involve reordering joins to filter early—apply the most selective predicates (lowest cardinality) before joining to large tables.
- **Statistics staleness is the root cause**: before applying hints, check if your table stats are current (`ANALYZE` in PostgreSQL, `UPDATE STATISTICS` in SQL Server). A fresh run of statistics often fixes bad plans without hints.
- **EXPLAIN ANALYZE is your diagnostic tool**: always run it on both the hinted and non-hinted version to confirm the hint changes the plan and improves actual runtime, not just estimated cost.
- **Database-specific syntax varies wildly**: memorize your target database's hint syntax (comments vs. keywords) and test in an interview environment—don't assume PostgreSQL syntax works in MySQL.
