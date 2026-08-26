---
date: 2026-08-26
phase: sql
topic: SQL anti-patterns: N+1 queries and implicit conversion overhead
---

# SQL anti-patterns: N+1 queries and implicit conversion overhead

*SQL for analytics and engineering*

## Concept

An **N+1 query problem** occurs when your application loops over results from an initial query and issues one query per row instead of joining or batching in SQL. For a list of 1,000 jobs, you'd fire 1 initial query + 1,000 follow-up queries instead of a single join. This multiplies network roundtrips, parsing overhead, and lock contention—especially catastrophic in analytics pipelines where you're processing millions of rows.

**Implicit type conversion overhead** happens when you compare columns of different types without explicit casting. SQL engines must convert values at runtime on every row evaluation, preventing index usage and forcing full table scans. A common case: comparing a VARCHAR job_id to an INTEGER in a WHERE clause, or comparing DATE columns to STRING literals without proper formatting.

Both patterns compound in analytics: a slow query that runs once might be acceptable, but when you're building ETL jobs, dashboards, or audit queries that execute hourly, shaving milliseconds per row multiplied by millions of rows yields hours of savings. The fix is always the same: **push work to SQL, batch operations, and be explicit about types in joins and filters.**

## Practice

**Problem:** You need to list all remote jobs posted in the last 30 days with their average salary *for jobs in that same location*. A naive approach loops: fetch remote jobs, then for each job_location, query the average. Write a single SQL query that avoids N+1 and ensures type safety.

```sql
SELECT 
    jp.job_id,
    jp.job_title_short,
    jp.job_location,
    jp.salary_year_avg,
    jp.job_posted_date,
    ROUND(AVG(jp2.salary_year_avg) OVER (
        PARTITION BY jp.job_location
    ), 2) AS avg_salary_by_location
FROM job_postings_fact jp
WHERE jp.job_work_from_home = TRUE
  AND jp.job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY jp.job_posted_date DESC;
```

**Why this works:** Window function partitions by location in a single pass instead of looping. All salary calculations happen server-side. The boolean comparison is direct (no implicit conversion). If you had a junction table, you'd use an explicit INNER JOIN with ON conditions matching exact types.

## Notes

- **Index killers:** Implicit conversions in WHERE clauses (`WHERE varchar_col = 123`) force database engines to scan every row; always cast explicitly or use string literals for VARCHAR columns.
- **N+1 in ETL:** Watch for loops over temporary tables or result sets—migrate to temp tables, CTEs, or window functions to batch within a single statement.
- **Related patterns:** Subquery explosion (correlated subqueries in SELECT), missing joins (Cartesian products from incomplete ON clauses), and inadequate filtering (pushing aggregation before WHERE).
- **Interview tip:** Ask "Is this one query or a loop?" Interviewers listen for this; articulate your choice and the performance trade-off.
- **Revisit:** Query explain plans (`EXPLAIN ANALYZE`), index design for JOIN conditions, and the cost of type casting in large datasets—these directly explain why anti-patterns hurt.
