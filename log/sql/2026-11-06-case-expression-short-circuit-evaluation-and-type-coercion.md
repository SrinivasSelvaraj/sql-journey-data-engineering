---
date: 2026-11-06
phase: sql
topic: CASE expression short-circuit evaluation and type coercion
---

# CASE expression short-circuit evaluation and type coercion

*SQL for analytics and engineering*

## Concept

CASE expressions in SQL do not short-circuit: **all branches are evaluated before the result is selected**, unlike `if` statements in most programming languages. This means that if you write `CASE WHEN condition THEN risky_calculation ELSE safe_value END`, the risky_calculation will execute regardless of whether the condition is true. Type coercion compounds this—SQL may implicitly convert types across branches, and if branches produce incompatible types, the database infers a common type, sometimes with silent truncation or unexpected casting behavior.

This matters most when you have expensive operations (division, string functions, casts) or operations that can fail (dividing by zero, accessing out-of-bounds array indices) in CASE branches. Without understanding that all branches execute, you may assume a guard condition prevents an error, only to encounter it in production. Type coercion is equally dangerous: a CASE that returns `INT` in one branch and `VARCHAR` in another will coerce the result, potentially losing precision or causing comparison failures downstream.

The practical rule: **treat CASE as a function that evaluates every branch, then coerces the result to a common type**. Write defensive queries by ensuring all branches can safely execute and produce compatible types, or restructure logic to avoid CASE where safety requires true short-circuiting.

## Practice

**Problem:** You want to calculate a bonus as 5% of salary for remote workers and 2% for on-site workers. However, some salary values are NULL. Write a query that safely computes bonus and avoids division or NULL surprises. Also return job title, salary, and the bonus.

```sql
SELECT
  job_title_short,
  salary_year_avg,
  CASE
    WHEN job_work_from_home = true AND salary_year_avg IS NOT NULL
      THEN salary_year_avg * 0.05
    WHEN job_work_from_home = false AND salary_year_avg IS NOT NULL
      THEN salary_year_avg * 0.02
    ELSE NULL
  END AS bonus_amount
FROM job_postings_fact
WHERE job_posted_date >= '2023-01-01'
ORDER BY salary_year_avg DESC NULLS LAST;
```

**Why this works:** The conditions explicitly check `IS NOT NULL` before arithmetic, so NULL salary values are caught before multiplication. Both branches return numeric types (INT or DECIMAL), so type coercion is safe. The ELSE clause returns NULL—consistent with the branches—rather than a default value that might hide missing data.

## Notes

- **All branches execute:** Don't rely on early conditions to prevent expensive or dangerous operations in later branches. Restructure using `WHERE` filters if you need true short-circuit safety.
- **Type coercion is silent:** A CASE returning `NUMERIC` in one branch and `VARCHAR` in another will coerce the entire result. Check expected types explicitly with `CAST()` to document intent and catch surprises.
- **NULL handling:** NULL in any CASE branch doesn't trigger the ELSE; use explicit `IS NOT NULL` checks in conditions. Mixing NULL and non-NULL branches can lead to unexpected type promotion.
- **Performance on large tables:** Avoid CASE branches with subqueries or function calls; use `JOIN` or `WITH` clauses instead. Complex CASE logic sometimes signals that a simpler query design exists.
- **Adjacent topics:** Connects to `COALESCE` (shorthand for NULL-safe defaults), computed columns in schema design, and query plan optimization (CASE can prevent index use if poorly structured).
