---
date: 2026-09-10
phase: sql
topic: Execution plan caching and parameter binding safety
---

# Execution plan caching and parameter binding safety

*SQL for analytics and engineering*

## Concept

Execution plan caching occurs when a database pre-compiles and reuses a query's access strategy (which indexes to scan, join order, sort methods) across multiple executions with different parameter values. Without parameterized queries, each unique literal value forces a fresh parse and plan, wasting CPU and memory. More critically, **parameter binding prevents SQL injection**: when you pass values as bound parameters rather than string concatenation, the database treats them as data, not executable code.

In analytics contexts, you often execute similar queries repeatedly—filtering by date range, user ID, or region. Caching the plan once and swapping parameters is 10–100× faster than reparsing. However, unsafe concatenation (`SELECT * FROM jobs WHERE location = '` + user_input + `'`) opens a hole: a malicious input like `' OR '1'='1` alters query logic. Parameterized queries eliminate this entirely because the parameter value never enters the SQL string itself.

The stakes are high in engineering: a cached plan optimized for one parameter distribution may be suboptimal for another (parameter sniffing), but this is a tuning problem, not a correctness one. Injection is a correctness *and* security problem.

## Practice

**Problem:** Write a query that accepts a user-provided job title substring and salary threshold as inputs. Return job IDs, titles, and salaries for jobs matching both filters. Ensure the query is safe from injection and reusable with caching.

```sql
-- Using parameterized query (e.g., in Python with psycopg2, or any SQL client)
-- Parameters: job_title_param (string), min_salary_param (integer)

SELECT 
    job_id,
    job_title_short,
    salary_year_avg
FROM job_postings_fact
WHERE job_title_short ILIKE '%' || $1 || '%'
  AND salary_year_avg >= $2
ORDER BY salary_year_avg DESC;

-- Call with parameters: $1 = 'Data Engineer', $2 = 100000
-- The database caches this plan; subsequent calls swap $1 and $2 values only.
```

## Notes

- **Never concatenate user input into SQL strings**, even in "safe" contexts like internal dashboards. Use parameterized queries everywhere; it's the default safest path.
- **Parameter sniffing**: a cached plan chosen for the first parameter set may be inefficient for later ones (e.g., plan optimized for rare value performs poorly on common value). Monitor slow queries and consider `RECOMPILE` hints or plan guides if critical.
- **Adjacent topics**: prepared statements (client-side plan caching), query hints (`OPTIMIZE FOR`), and statistics freshness all interact with plan caching behavior.
- **Test with real distributions**: a query fast on 1% of data may be slow on 50%. Cache plans based on representative parameter values, or use adaptive query optimization (SQL Server) if available.
- **Logging**: enable query plan logging in development to confirm plans are being reused; in production, track plan cache hit ratios to spot recompilation storms.
