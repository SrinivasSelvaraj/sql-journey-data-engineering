---
date: 2026-10-05
phase: sql
topic: NULLS FIRST and NULLS LAST in ORDER BY
---

# NULLS FIRST and NULLS LAST in ORDER BY

*SQL for analytics and engineering*

## Concept

`NULLS FIRST` and `NULLS LAST` are explicit clauses in the `ORDER BY` statement that control where NULL values appear in sorted results. By default, database behavior varies: PostgreSQL and Oracle treat NULLs as highest (first in ascending, last in descending), while SQL Server and MySQL treat them as lowest. This inconsistency creates bugs when moving queries across systems or when the default behavior doesn't match business logic.

The clause matters most when NULLs have semantic meaning—for example, sorting job postings by `salary_year_avg` where NULL means "not disclosed" and should appear last, separate from actual salary data. Without explicit specification, you risk either silently incorrect ordering or having to filter NULLs separately with `WHERE ... IS NOT NULL`, which changes the result set entirely.

Forgetting to specify null handling becomes critical in ranking queries, pagination, and analytics where the first or last row carries business significance (e.g., "show me the 10 highest-paid jobs" should exclude undisclosed salaries from the top 10, or explicitly show them last).

## Practice

**Problem:** You need to list all job postings ordered by `salary_year_avg` descending (highest first), but NULL salaries should appear at the end of the result set, not mixed with real values.

```sql
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_location
FROM job_postings_fact
ORDER BY salary_year_avg DESC NULLS LAST;
```

## Notes

- **Database portability:** SQL standard (`NULLS FIRST/LAST`) is supported in PostgreSQL, Oracle, and SQLite; SQL Server and MySQL require conditional expressions like `ORDER BY CASE WHEN col IS NULL THEN 1 ELSE 0 END, col DESC` as a workaround.
- **Descending gotcha:** With `DESC`, you often still want `NULLS LAST` (not automatically true)—NULLs don't automatically flip to the other end; you must specify.
- **Performance:** Null handling is cheap; the real cost is the sort itself. Don't use null positioning as a substitute for filtering.
- **Ties with ranking windows:** When using `ROW_NUMBER()` or `DENSE_RANK()`, apply `NULLS LAST` *inside* the window's `ORDER BY` clause to ensure consistent rank assignment.
- **Adjacent skill:** This pairs with `COALESCE()` / `IFNULL()` for replacing NULLs, and with filtering logic—know when to exclude vs. explicitly order them.
