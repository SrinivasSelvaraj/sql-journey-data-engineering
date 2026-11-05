---
date: 2026-11-05
phase: sql
topic: Null handling: three-valued logic and aggregate edge cases
---

# Null handling: three-valued logic and aggregate edge cases

*SQL for analytics and engineering*

## Concept

Three-valued logic in SQL means every comparison can yield TRUE, FALSE, or **NULL** — and NULL propagates in unexpected ways. When you write `WHERE salary > 100000`, rows with NULL salary don't appear in results (they're filtered out, not returned as FALSE). This is correct by SQL standard but trips up analysts who expect NULL to mean "unknown or missing" and think it should be included or excluded differently. Aggregate functions handle NULL silently: `COUNT(*)` includes NULL rows, but `COUNT(salary)` skips them; `SUM()`, `AVG()`, `MAX()` all ignore NULLs, which can make summary queries seem correct when they're masking data quality issues.

Edge cases emerge in GROUP BY logic, CASE statements, and joins. A `LEFT JOIN` preserves unmatched rows as NULL, but `COUNT(right_table_column)` will skip those rows entirely — so `COUNT(*)` and `COUNT(right_col)` give different results on the same grouped data, revealing which groups had no match. CASE WHEN conditions also stop at the first TRUE; if you don't explicitly handle NULL, it falls through to ELSE, creating silent logic errors. Window functions and DISTINCT also interact poorly with NULL: two NULL values are considered equal for DISTINCT but unequal in some ranking contexts.

## Practice

**Problem:** You need a dashboard showing average salary by job title, count of postings, and percentage of work-from-home jobs. Some salary data and work_from_home flags are NULL. Write a query that correctly counts total postings, counts non-null salaries, and computes WFH percentage without division-by-zero errors.

```sql
SELECT
  job_title_short,
  COUNT(*) AS total_postings,
  COUNT(salary_year_avg) AS postings_with_salary,
  ROUND(AVG(salary_year_avg), 0) AS avg_salary,
  ROUND(
    100.0 * SUM(CASE WHEN job_work_from_home = TRUE THEN 1 ELSE 0 END) 
    / NULLIF(COUNT(CASE WHEN job_work_from_home IS NOT NULL THEN 1 END), 0),
    1
  ) AS pct_work_from_home
FROM job_postings_fact
GROUP BY job_title_short
HAVING COUNT(salary_year_avg) > 0
ORDER BY avg_salary DESC;
```

Key moves: `COUNT(*)` for total; `COUNT(salary_year_avg)` to count non-NULL salaries only; `SUM(CASE WHEN ... IS NOT NULL)` to count rows where WFH flag exists; `NULLIF(..., 0)` to prevent division by zero; `HAVING COUNT(salary_year_avg) > 0` to exclude titles with no salary data.

## Notes

- **Common mistake:** Using `COUNT(column)` without realizing it silently drops NULLs, then comparing to `COUNT(*)` and being confused by the mismatch. Always ask: am I counting rows or counting non-null values?
- **Adjacent topics:** COALESCE and IFNULL for substituting defaults; IS NULL / IS NOT NULL conditions for explicit filtering; CASE WHEN for conditional aggregation (safer than WHERE for segmented logic).
- **Query plan impact:** Filters with `column IS NOT NULL` can help the planner push predicates down; missing NULL handling forces the optimizer to materialize more rows into aggregations.
- **Joins and NULL:** When joining, unmatched right-side rows become NULL. `COUNT(*)` vs. `COUNT(right_column)` reveals join quality; use COALESCE to replace join-generated NULLs before aggregating if you want unmatched rows to contribute.
- **Revisit:** Test your NULL logic on real data with missing values; mock NULL in CTEs to validate edge cases before production. Use `HAVING COUNT(column) > 0` to exclude groups where a key measure is entirely NULL.
