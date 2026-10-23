---
date: 2026-10-23
phase: sql
topic: SQL compilation and caching strategies
---

# SQL compilation and caching strategies

*SQL for analytics and engineering*

## Concept

SQL compilation converts a query into an executable plan; caching stores compiled plans to avoid recompilation overhead. Most databases (PostgreSQL, MySQL, Snowflake) compile queries once and cache the plan, reusing it on subsequent identical executions. This matters because compilation includes parsing, semantic validation, and cost-based optimization—steps that can consume 10–30% of execution time on small queries. Without caching, repeated queries (common in dashboards, APIs, and batch jobs) recompile unnecessarily, wasting CPU and increasing latency.

Plan caching breaks down when:
- **Parameter values change significantly** (e.g., filtering 10 rows vs. 10 million rows)—optimizers may choose different join orders or index strategies, making a cached plan suboptimal
- **Table statistics are stale**—the planner's cardinality estimates become wrong, leading to poor decisions
- **Queries are dynamically generated** without parameter binding—each variant is compiled fresh, defeating the cache

The key to effective caching in analytics is using **parameterized queries** (bind variables) so logically identical queries with different values share one compiled plan.

## Practice

**Problem:** You're building a dashboard that filters job postings by location and salary range. Write a query that can be safely cached and reused across different parameter values without performance degradation.

```sql
-- Use parameterized query (bind variables) for caching efficiency
-- Parameters: location (string), min_salary (integer), max_salary (integer)

PREPARE get_jobs (TEXT, INT, INT) AS
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_location,
  job_posted_date
FROM job_postings_fact
WHERE job_location = $1
  AND salary_year_avg >= $2
  AND salary_year_avg <= $3
  AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
ORDER BY salary_year_avg DESC
LIMIT 100;

-- Execute with different parameters; plan is compiled once
EXECUTE get_jobs('New York, NY', 100000, 200000);
EXECUTE get_jobs('San Francisco, CA', 120000, 250000);
```

**Why this works:** The query structure is identical; only values change. The optimizer compiles once with generic cardinality assumptions, producing a robust plan. Avoid string concatenation (`WHERE job_location = '` + input + `'`) which creates a new query string each time.

## Notes

- **Stale statistics trap:** If `job_postings_fact` grows from 50k to 5M rows but `ANALYZE` isn't run, the cached plan assumes old cardinality and chooses slow nested loops instead of hash joins. Refresh statistics before switching queries to production data volumes.

- **Parameter sniffing** (SQL Server risk): A cached plan optimized for the first parameter set (e.g., `job_location = 'rare-city'`) may be terrible for the second (e.g., `job_location = 'New York'`). Databases handle this differently; PostgreSQL is generally safe, but test production patterns.

- **CTEs and subqueries:** Materialization decisions (whether to build temp results or inline logic) may depend on the optimizer, not caching. Rewrite complex nested queries as CTEs if you suspect plan variance.

- **Adjacent topic—query plan analysis:** Use `EXPLAIN` (PostgreSQL) or `EXPLAIN PLAN FOR` (Oracle/Snowflake) to inspect whether your parameterized query produces a single, sensible plan, or if the optimizer is making risky assumptions.

- **Connection pooling:** Caching lives per connection (or per session in some databases). If your application opens new connections for each query, you lose cache benefits. Use connection pooling (PgBouncer, HikariCP) to amortize compilation cost.
