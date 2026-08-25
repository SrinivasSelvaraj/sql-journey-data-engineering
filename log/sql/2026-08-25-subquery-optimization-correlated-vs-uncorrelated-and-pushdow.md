---
date: 2026-08-25
phase: sql
topic: Subquery optimization: correlated vs uncorrelated and pushdown
---

# Subquery optimization: correlated vs uncorrelated and pushdown

*SQL for analytics and engineering*

## Concept

A **correlated subquery** references columns from the outer query, executing once per outer row—often causing full table scans and N+1 query patterns. An **uncorrelated subquery** runs once, returns a result set, and the outer query filters against it; databases can optimize this independently. **Predicate pushdown** means the query optimizer moves filter conditions (WHERE clauses) into subqueries or joins as early as possible, reducing rows before expensive operations like aggregations or joins.

Subquery optimization matters because correlated subqueries can degrade from milliseconds to minutes on large tables. A naive approach like `SELECT * FROM jobs j WHERE salary > (SELECT AVG(salary) FROM jobs WHERE job_title_short = j.job_title_short)` re-evaluates the subquery for every row. Pushdown optimization is critical: if you filter on `job_work_from_home = true` inside a subquery before joining, you eliminate 90% of rows before the join happens, not after.

Without optimization awareness, you write queries that appear correct but time out in production. Understanding query plans (EXPLAIN in PostgreSQL, query execution in Snowflake) reveals whether your subquery runs once or millions of times, and whether filters are applied at the right stage.

## Practice

**Problem:** Find job titles where the average salary is above the overall median salary across all jobs, and only count remote positions.

```sql
-- Optimized: uncorrelated subquery with pushdown
WITH remote_jobs AS (
  SELECT job_title_short, salary_year_avg
  FROM job_postings_fact
  WHERE job_work_from_home = true
    AND salary_year_avg IS NOT NULL
),
median_salary AS (
  SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) AS med_sal
  FROM remote_jobs
)
SELECT 
  job_title_short,
  AVG(salary_year_avg) AS avg_sal,
  COUNT(*) AS job_count
FROM remote_jobs
CROSS JOIN median_salary
WHERE salary_year_avg > median_salary.med_sal
GROUP BY job_title_short
ORDER BY avg_sal DESC;
```

Why this works: The `WHERE job_work_from_home = true` is pushed down into the CTE, filtering before aggregation. The median is calculated once on the filtered set (uncorrelated), not recalculated per job title. A correlated alternative would re-scan all jobs for every title, multiplying work unnecessarily.

## Notes

- **Correlated subqueries are slower by default:** Use `EXPLAIN ANALYZE` to see if your subquery shows "rows=X" executed multiple times; that's your red flag. Rewrite with `JOIN`, `IN`, or `EXISTS` (with pushdown) when possible.
- **IN vs EXISTS:** `SELECT * FROM jobs WHERE job_id IN (SELECT job_id FROM applications)` and `EXISTS` variants are both uncorrelated; `EXISTS` can be faster if the inner query is selective and can short-circuit.
- **Aggregate predicates demand care:** Filters like `HAVING AVG(salary) > X` happen after grouping; move filters to WHERE (before grouping) when they apply to raw rows, not aggregates.
- **CTEs and materialization:** Some databases materialize CTEs (calculate once, store temporarily), enabling pushdown on subsequent uses. Others don't; check your EXPLAIN output. In Snowflake/BigQuery, CTEs are often inlined, so they don't guarantee single execution.
- **Dimensional context:** In star-schema analytics (common in job posting datasets), correlated subqueries on fact tables are especially slow because facts are high-cardinality; always denormalize or use JOINs to dimension tables instead.
