---
date: 2026-08-25
phase: sql
topic: Common table expressions: scope, materialization hints and recursion
---

# Common table expressions: scope, materialization hints and recursion

*SQL for analytics and engineering*

## Concept

Common table expressions (CTEs) are named, temporary result sets defined with the `WITH` clause that exist only for the duration of a single query. They serve three critical purposes: improving readability by breaking complex queries into logical chunks, enabling code reuse within a single statement, and—most importantly—providing control over query execution and materialization. Without CTEs, nested subqueries become deeply indented and difficult to optimize; with them, you can name intermediate results and reason about query plans layer by layer.

CTEs can be materialized (computed once and stored in memory) or inlined (merged into the main query by the optimizer), depending on the database engine and hints you provide. Most modern engines default to inlining non-recursive CTEs unless you explicitly request materialization (e.g., `MATERIALIZED` in PostgreSQL or `MATERIALIZE` in Snowflake). This matters because a materialized CTE acts as a "checkpoint" that prevents the optimizer from pushing predicates down, which can be good (avoiding redundant work) or bad (losing filter pushdown opportunities). Recursive CTEs—those that reference themselves—must be materialized and are essential for hierarchical or graph problems like organizational trees, bill-of-materials, and path-finding queries.

## Practice

**Problem:** Find the job title with the highest average salary among remote positions posted in 2024. Then, for that job title, count how many remote positions exist and what percentage of all postings (remote or not) they represent.

```sql
WITH remote_2024 AS (
  SELECT
    job_title_short,
    salary_year_avg,
    job_posted_date
  FROM job_postings_fact
  WHERE job_work_from_home = TRUE
    AND YEAR(job_posted_date) = 2024
),
title_avg_salary AS (
  SELECT
    job_title_short,
    AVG(salary_year_avg) AS avg_salary,
    COUNT(*) AS remote_count
  FROM remote_2024
  GROUP BY job_title_short
),
top_title AS (
  SELECT job_title_short
  FROM title_avg_salary
  ORDER BY avg_salary DESC
  LIMIT 1
),
all_postings_count AS (
  SELECT COUNT(*) AS total_postings
  FROM job_postings_fact
  WHERE YEAR(job_posted_date) = 2024
)
SELECT
  t.job_title_short,
  tas.avg_salary,
  tas.remote_count,
  apc.total_postings,
  ROUND(100.0 * tas.remote_count / apc.total_postings, 2) AS pct_of_all
FROM top_title t
JOIN title_avg_salary tas ON t.job_title_short = tas.job_title_short
CROSS JOIN all_postings_count apc;
```

## Notes

- **Materialization double-edged sword:** Always check your query plan. If a CTE filters heavily, materializing it avoids re-filtering in downstream joins. If a CTE is just a thin wrapper, inlining lets the optimizer push down WHERE clauses. Test both strategies when performance is critical.

- **Recursive CTE gotcha:** Recursive CTEs require an anchor (non-recursive) query and one or more recursive members joined with `UNION ALL`. The recursion terminates when no new rows are produced; infinite loops are possible if your termination condition is wrong. Always include depth limits or visit tracking to prevent runaway execution.

- **Scope and naming conflicts:** CTEs are scoped to a single statement and are not stored objects. If you reference a CTE name in a subquery, it must be defined in the same top-level `WITH` block. You cannot nest `WITH` clauses inside subqueries in standard SQL (though some engines allow it).

- **Adjacent skills to strengthen:** Understanding how `EXPLAIN` or `EXPLAIN ANALYZE` reveals whether CTEs are inlined or materialized; familiarity with window functions (often faster than CTEs for running totals); awareness of when to use temporary tables instead for multi-query workflows.

- **Common mistake:** Overusing CTEs for "readability" when a single well-formatted query is clearer; or creating CTEs that are only referenced once, which adds cognitive load without benefit. Reserve CTEs for cases where they genuinely reduce nesting depth or enable logical reuse.
