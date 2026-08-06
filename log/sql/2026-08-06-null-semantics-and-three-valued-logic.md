---
date: 2026-08-06
phase: sql
topic: NULL semantics and three-valued logic
---

# NULL semantics and three-valued logic

*SQL for analytics and engineering*

## Concept

NULL represents an unknown or missing value, not zero or empty string. SQL uses three-valued logic (TRUE, FALSE, NULL) where any comparison or operation involving NULL typically returns NULL, not FALSE. This is critical because `WHERE salary > 50000` will silently exclude rows where salary is NULL—they won't appear in results, but they also won't trigger errors. Without understanding NULL semantics, you'll write queries that accidentally filter out unknown data and produce incomplete result sets that appear correct until tested against edge cases.

The consequences are subtle and dangerous: `WHERE col = NULL` returns zero rows (use `IS NULL` instead); `NOT IN (list_with_nulls)` returns zero rows even when it shouldn't; joins on nullable columns silently drop unmatched NULLs; and aggregate functions like COUNT(*) and SUM() treat NULL differently (`COUNT(*)` counts NULLs, but `COUNT(col)` skips them). In analytics, this means your cohort sizes, revenue totals, and user funnel metrics can be systematically wrong without obvious red flags.

## Practice

**Problem:** Find the count of job postings and average salary for each job title, but separately report how many postings are missing salary data. Include only titles with at least 2 postings total.

```sql
SELECT
  job_title_short,
  COUNT(*) AS total_postings,
  COUNT(salary_year_avg) AS postings_with_salary,
  COUNT(*) - COUNT(salary_year_avg) AS postings_missing_salary,
  ROUND(AVG(salary_year_avg), 0) AS avg_salary
FROM job_postings_fact
GROUP BY job_title_short
HAVING COUNT(*) >= 2
ORDER BY total_postings DESC;
```

**Key points:** `COUNT(*)` counts all rows including NULLs; `COUNT(salary_year_avg)` counts only non-NULL values; the difference isolates missing data. `AVG()` automatically excludes NULLs, so your average isn't dragged down by unknowns. If you had used `WHERE salary_year_avg IS NOT NULL` at the top level, you'd lose sight of which titles have incomplete data.

## Notes

- **Common mistake:** Using `WHERE col = NULL` or `WHERE col != NULL`—always use `IS NULL` and `IS NOT NULL`. Equality comparisons with NULL always return NULL (falsy), not TRUE or FALSE.
- **Aggregate gotcha:** `COUNT(*)` ≠ `COUNT(col)` when NULLs exist; `SUM()` and `AVG()` skip NULLs entirely, which can silently undercount; use `COALESCE()` to provide defaults if you need different behavior.
- **JOIN trap:** INNER JOIN drops unmatched rows including those with NULL join keys; LEFT JOIN preserves them but produces NULL in the right table. Be explicit about whether your join keys can be NULL.
- **IN / NOT IN:** `WHERE col IN (1, 2, NULL)` works like OR; but `WHERE col NOT IN (1, 2, NULL)` returns zero rows because `col NOT IN list_with_null` is never TRUE (NULL poisons the NOT IN logic).
- **Adjacent topic:** COALESCE, NULLIF, and CASE WHEN are your tools for handling NULL strategically; three-valued logic also underpins window function PARTITION BY behavior and recursive CTEs.
