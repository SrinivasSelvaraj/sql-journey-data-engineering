---
date: 2026-10-03
phase: sql
topic: NULL handling in aggregate functions and joins
---

# NULL handling in aggregate functions and joins

*SQL for analytics and engineering*

## Concept

NULL values are **absent or unknown data**, not zero or empty strings. Aggregate functions (COUNT, SUM, AVG, MAX, MIN) **skip NULLs by default**, which silently changes your result set if you're not careful. JOINs treat NULL as unequal to any value, including other NULLs—so `table1.col = table2.col` will never match rows where either side is NULL. This means outer joins can produce unexpected NULLs in result columns, and inner joins silently drop unmatched rows with NULL keys.

The danger is subtle: a query may run without error but return incomplete or misleading answers. For example, `SUM(salary)` skips NULL salary rows entirely rather than treating them as zero. Similarly, a LEFT JOIN on a column containing NULLs won't match those rows from the left table, defeating the purpose of the outer join. Understanding NULL semantics is critical for correctness—you must explicitly decide whether to coalesce, filter, or count NULLs.

## Practice

**Problem:** Calculate the average salary for each job title, and count how many postings had salary data vs. missing salary data. Identify which job titles have the most incomplete salary information. Return results sorted by missing count descending.

```sql
SELECT 
  job_title_short,
  COUNT(*) AS total_postings,
  COUNT(salary_year_avg) AS postings_with_salary,
  COUNT(*) - COUNT(salary_year_avg) AS missing_salary_count,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary
FROM job_postings_fact
GROUP BY job_title_short
HAVING COUNT(*) - COUNT(salary_year_avg) > 0
ORDER BY missing_salary_count DESC;
```

**Why this works:** `COUNT(*)` counts all rows including NULLs; `COUNT(salary_year_avg)` counts only non-NULL values. The difference reveals gaps. `AVG()` automatically excludes NULLs, so the average is computed only on valid salaries. The HAVING clause filters to job titles with at least one missing value.

## Notes

- **COUNT(*) vs. COUNT(col):** Always use COUNT(*) to count total rows; use COUNT(specific_column) to count non-NULL values. Confusing these is a common bug.
- **Aggregate + NULL interaction:** SUM, AVG, MAX, MIN all skip NULLs. If all rows in a group are NULL, the aggregate returns NULL (except COUNT(*) returns 0). This can cause GROUP BY results to vanish silently.
- **JOIN + NULL:** Use COALESCE or explicit filters if you need to match on nullable columns. Consider whether NULL should be treated as a distinct value or excluded entirely before the join.
- **CASE + COALESCE in aggregates:** Wrap aggregates in CASE to handle NULLs conditionally, e.g., `SUM(CASE WHEN col IS NOT NULL THEN col ELSE 0 END)` to treat missing as zero rather than skip it.
- **Revisit:** NULL handling connects to data quality checks (profiling), window functions (which also skip NULLs), and WHERE clause filtering (which excludes NULL matches—use IS NULL/IS NOT NULL explicitly).
