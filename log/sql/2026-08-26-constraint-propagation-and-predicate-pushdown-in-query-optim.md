---
date: 2026-08-26
phase: sql
topic: Constraint propagation and predicate pushdown in query optimization
---

# Constraint propagation and predicate pushdown in query optimization

*SQL for analytics and engineering*

## Concept

Constraint propagation and predicate pushdown are query optimization techniques that filter data as early as possible in the execution plan, rather than after joins or aggregations. When you apply a WHERE clause, the optimizer attempts to "push down" that filter closer to the table scan—ideally before rows are read into memory or before expensive operations like joins. Constraint propagation takes this further: if you filter on one column, the optimizer can infer constraints on related columns (e.g., if `salary > 100000`, then we can also infer `job_postings_fact` must exist) and apply those derived filters earlier.

Without pushdown and propagation, a query might join two large tables first, then filter the result—moving millions of rows through the pipeline unnecessarily. Modern query planners (Postgres, Snowflake, BigQuery) handle this automatically, but writing SQL that *enables* pushdown matters: placing predicates in WHERE clauses rather than HAVING, avoiding functions that obscure column references, and joining on indexed columns all help the optimizer recognize opportunities to filter early.

## Practice

**Problem:** You're analyzing remote job postings with high salaries. Write a query that finds all remote jobs posted in 2024 with average salary over $120k, grouped by job title. Without proper predicate pushdown, this could scan millions of rows before filtering.

```sql
SELECT
  job_title_short,
  COUNT(*) AS posting_count,
  AVG(salary_year_avg) AS avg_salary
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND EXTRACT(YEAR FROM job_posted_date) = 2024
  AND salary_year_avg > 120000
GROUP BY job_title_short
HAVING COUNT(*) > 5
ORDER BY avg_salary DESC;
```

**Why this works:** The WHERE clause filters on `job_work_from_home`, `job_posted_date`, and `salary_year_avg` *before* grouping. If an index exists on any of these columns, the planner can use it to eliminate rows at scan time. The HAVING clause (`COUNT(*) > 5`) applies *after* aggregation, which is correct—it filters groups, not rows. EXTRACT in the WHERE clause may prevent index use on `job_posted_date`; if performance matters, use `job_posted_date >= '2024-01-01' AND job_posted_date < '2025-01-01'` instead.

## Notes

- **Avoid pushing functions into WHERE:** `WHERE YEAR(date_col) = 2024` often prevents index use; prefer range predicates like `date_col >= '2024-01-01'`.
- **HAVING vs. WHERE:** HAVING filters after GROUP BY; WHERE filters before. Use WHERE for row-level constraints, HAVING for aggregate constraints. Misplacing them blocks pushdown.
- **Nullable columns and logic:** Predicates on nullable columns interact with three-valued logic; ensure your filters account for NULL if it matters (e.g., `salary_year_avg > 100000` excludes NULLs, which may be intentional).
- **Joins and predicate inference:** In a join, filtering on one table's column can sometimes infer a filter on the joined table. Modern planners detect this; writing explicit predicates on both tables doesn't hurt and aids readability.
- **Revisit:** Check your database's EXPLAIN PLAN output to verify predicates are pushed down. Tools like pgAdmin, Snowflake's query profile, or BigQuery's execution details show filter placement and cardinality reduction.
