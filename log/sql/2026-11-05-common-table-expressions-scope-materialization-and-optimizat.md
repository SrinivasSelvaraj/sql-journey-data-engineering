---
date: 2026-11-05
phase: sql
topic: Common table expressions: scope, materialization and optimization
---

# Common table expressions: scope, materialization and optimization

*SQL for analytics and engineering*

## Concept

A Common Table Expression (CTE) is a named temporary result set defined within a query using the `WITH` clause, scoped only to that query's execution. CTEs improve readability by breaking complex logic into named steps and allow recursion, but they do **not** automatically materialize or optimize—the database query planner decides whether to inline (expand) or materialize (compute once and store temporarily) each CTE. Materialization matters when a CTE is referenced multiple times or contains expensive operations; inlining matters when a CTE is simple and filtering upstream would reduce downstream work. Understanding your database's CTE handling (PostgreSQL inlines by default; SQL Server may materialize) is critical for performance tuning.

CTEs fail silently when scope assumptions break: a CTE defined in one branch of a UNION is not accessible in another, recursive CTEs without proper termination conditions cause infinite loops, and over-nesting CTEs without considering materialization can turn a simple query into a Cartesian-product nightmare. The most common performance trap is writing a CTE that filters or aggregates, then joining it multiple times, expecting the database to reuse the result—but if inlining occurs, you've just duplicated computation. Always test query plans and consider explicit indexes or materialized views for frequently reused expensive CTEs.

## Practice

**Problem:** Find the average salary for remote senior-level roles posted in the last 90 days, then return only those job titles that appear in more than one posting at that average salary level.

```sql
WITH recent_remote_senior AS (
  SELECT 
    job_title_short,
    salary_year_avg,
    job_posted_date
  FROM job_postings_fact
  WHERE job_work_from_home = TRUE
    AND job_title_short LIKE '%Senior%'
    AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
),
salary_stats AS (
  SELECT 
    job_title_short,
    AVG(salary_year_avg) AS avg_salary,
    COUNT(*) AS posting_count
  FROM recent_remote_senior
  GROUP BY job_title_short
  HAVING COUNT(*) > 1
)
SELECT 
  job_title_short,
  avg_salary,
  posting_count
FROM salary_stats
ORDER BY avg_salary DESC;
```

## Notes

- **Inlining vs. materialization trade-off**: if a CTE is referenced once, inlining usually wins; if referenced 2+ times or contains GROUP BY/aggregates, materialization or explicit indexing saves cost. Always check `EXPLAIN` output.
- **Scope and UNION pitfall**: CTEs are scoped to the entire query, but each branch of a UNION sees the same CTE definitions—don't assume a CTE defined before a UNION is unavailable after. Conversely, a CTE defined inside a subquery is *not* visible outside it.
- **Recursive CTEs require discipline**: anchor (base case) must terminate, and recursive member must reference the same CTE name without cycles. Missing the `UNION ALL` or termination condition causes runaway queries.
- **Adjacent optimization**: window functions (`ROW_NUMBER()`, `RANK()`) often replace multi-level CTEs; subqueries in `FROM` clauses may offer better plan control than CTEs in some engines; materialized views solve the "reused expensive CTE" problem permanently.
- **Readability vs. performance**: CTEs win on clarity but can hide inefficient logic. Flatten and push filters down (into the innermost CTE) rather than filtering at the top level.
