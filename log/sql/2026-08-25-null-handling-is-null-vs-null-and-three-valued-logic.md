---
date: 2026-08-25
phase: sql
topic: NULL handling: IS NULL vs = NULL and three-valued logic
---

# NULL handling: IS NULL vs = NULL and three-valued logic

*SQL for analytics and engineering*

## Concept

NULL in SQL represents the absence of a value, not an empty string or zero. Critically, NULL comparisons behave differently than you might expect: `column = NULL` always returns UNKNOWN (not TRUE or FALSE), never matching rows—even rows where the column is NULL. This is three-valued logic: TRUE, FALSE, and UNKNOWN. You must use `IS NULL` or `IS NOT NULL` to test for NULL explicitly. Without this distinction, queries silently exclude NULL rows, leading to incomplete result sets and hard-to-debug analytics errors.

The reason: SQL treats NULL as "unknown value" rather than "missing value." Comparing an unknown to anything—even another unknown—yields UNKNOWN. When you filter with `WHERE column = NULL`, rows with NULL fail the condition (UNKNOWN ≠ TRUE) and are dropped. This is mathematically sound but operationally dangerous: it means `WHERE salary_year_avg = NULL` returns zero rows even if your table has thousands of NULL salaries. Three-valued logic also affects JOINs, CASE statements, and aggregate functions, making NULL-awareness essential for correct analytics.

## Practice

**Problem:** You're analyzing job postings and need to count how many jobs have missing salary data AND are work-from-home roles. Your first attempt counts far fewer rows than expected.

```sql
-- WRONG: Returns 0 or too few rows
SELECT COUNT(*)
FROM job_postings_fact
WHERE salary_year_avg = NULL AND job_work_from_home = TRUE;

-- CORRECT: Use IS NULL
SELECT COUNT(*)
FROM job_postings_fact
WHERE salary_year_avg IS NULL AND job_work_from_home = TRUE;

-- Also correct: Explicit three-valued logic with COALESCE
SELECT COUNT(*)
FROM job_postings_fact
WHERE COALESCE(salary_year_avg, -1) = -1 AND job_work_from_home = TRUE;
```

The first query returns 0 because `salary_year_avg = NULL` evaluates to UNKNOWN for every row, failing the WHERE filter. The second correctly identifies rows where salary is absent.

## Notes

- **CASE statements trap:** `CASE WHEN column = NULL THEN ... END` will never trigger; use `CASE WHEN column IS NULL THEN ... END` instead.
- **JOIN gotcha:** `ON table1.id = table2.id` will not match rows where either id is NULL, even if both are NULL. Use `ON table1.id IS NOT DISTINCT FROM table2.id` (PostgreSQL) or `COALESCE` logic to join on NULLs intentionally.
- **Aggregates and NULL:** Functions like `SUM()`, `AVG()`, `COUNT()` skip NULL values by design; `COUNT(*)` counts rows, `COUNT(column)` counts non-NULL values only.
- **Testing strategy:** When debugging unexpected row counts, always check for NULL presence with `WHERE column IS NULL` or `... AND column IS NOT NULL` to verify filter assumptions.
- **Related:** Three-valued logic connects to constraint design (NOT NULL constraints), COALESCE/NULLIF for NULL manipulation, and performance (NULL columns sometimes need separate indexes or partitioning).
