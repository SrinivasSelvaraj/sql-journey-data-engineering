---
date: 2026-10-22
phase: sql
topic: Statistics gathering and query plan stability
---

# Statistics gathering and query plan stability

*SQL for analytics and engineering*

## Concept

Statistics gathering is the process of analyzing table distributions, cardinality, and data characteristics so the query optimizer can make informed decisions about execution plans. Without accurate statistics, the optimizer may choose full table scans over index seeks, nested loops over hash joins, or incorrect join orders—even when better plans exist. This becomes critical in production systems where the same query runs repeatedly; a suboptimal plan chosen once can execute millions of times.

Query plan stability means the optimizer consistently selects the same (good) plan across runs, rather than flip-flopping based on stale or missing statistics. In analytics workloads with large fact tables, a single poor plan choice can mean the difference between a 100ms query and a 30-minute hang. Statistics decay over time as data changes, and certain operations (bulk loads, partition switches) can invalidate assumptions the optimizer made during compilation.

The practical impact: after a large ETL load, you may need to manually refresh statistics; without this, queries that worked yesterday may suddenly timeout. In interview conditions, you should be able to reason about whether a table likely has stale statistics based on query performance and execution plan changes.

## Practice

**Problem:** The `job_postings_fact` table receives a daily load of 50,000 new rows. A report query that calculates average salary by job title has started taking 45 seconds instead of the usual 2 seconds. The query plan shows a full table scan instead of an expected index seek + aggregation. Assume statistics were last gathered 30 days ago. Write the command to refresh statistics and rerun the query.

```sql
-- Refresh statistics on the fact table
-- PostgreSQL
ANALYZE job_postings_fact;

-- SQL Server
UPDATE STATISTICS job_postings_fact;

-- Snowflake (automatic, but can trigger refresh)
REFRESH TABLE STATISTICS job_postings_fact;

-- Then rerun the original query
SELECT 
  job_title_short,
  AVG(salary_year_avg) AS avg_salary,
  COUNT(*) AS posting_count
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY job_title_short
ORDER BY avg_salary DESC;
```

## Notes

- **Stale statistics after bulk loads**: Full ETL jobs or partition switches can invalidate cardinality estimates; always gather stats immediately after major data movements in production pipelines.
- **Index selection depends on stats**: Without accurate row count and selectivity estimates, the optimizer may choose a full scan even when an index would be faster; this is especially painful when 90% of rows match a filter condition but stats say 5%.
- **Platform differences matter**: PostgreSQL uses `ANALYZE`, SQL Server uses `UPDATE STATISTICS`, Snowflake/BigQuery largely handle this automatically but allow manual triggers; know your target system's commands.
- **Connects to**: query hints (forcing a plan when stats are wrong), execution plan reading (EXPLAIN/EXPLAIN PLAN), and partition elimination strategies in fact tables.
- **Interview red flag**: If a query suddenly degrades in performance without code changes, suspect stale statistics first—this shows you understand the optimizer's dependency on metadata, not just SQL syntax.
