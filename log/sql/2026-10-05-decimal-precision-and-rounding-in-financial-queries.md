---
date: 2026-10-05
phase: sql
topic: Decimal precision and rounding in financial queries
---

# Decimal precision and rounding in financial queries

*SQL for analytics and engineering*

## Concept

Financial calculations in SQL demand explicit precision handling because floating-point arithmetic accumulates rounding errors—especially dangerous when aggregating thousands of rows or chaining operations. The `DECIMAL` (or `NUMERIC`) data type with fixed precision and scale is the standard: `DECIMAL(10, 2)` means 10 total digits with 2 after the decimal point, guaranteeing exact representation for currency. Without this, `FLOAT` or `DOUBLE` can silently lose cents; multiplying salary by a percentage, then summing across millions of employees, compounds truncation into material errors.

Rounding strategy matters as much as data type. SQL supports `ROUND()`, `TRUNCATE()`, and `CEIL()/FLOOR()`, but financial contexts require explicit rounding rules: most accounting uses "round half up" (banker's rounding is half-to-even, less common in finance). When dividing salaries by months, calculating bonuses, or computing averages, you must round *before* aggregating to avoid cascading precision loss. Cast intermediates to `DECIMAL` and set scale early.

Indexes and query performance also depend on this: `DECIMAL` columns are indexable and predictable in size, while `FLOAT` introduces comparison inconsistencies. Always validate your rounding in edge cases (salaries like $99,999.99 divided by 12 months) and test with actual financial datasets before production.

## Practice

**Problem:** Calculate the average annual salary by job title, rounded to the nearest cent, ensuring no floating-point errors accumulate. Return only titles with an average salary ≥ $80,000. Order by average salary descending.

```sql
SELECT 
  job_title_short,
  ROUND(AVG(CAST(salary_year_avg AS DECIMAL(12, 2))), 2) AS avg_salary
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY job_title_short
HAVING ROUND(AVG(CAST(salary_year_avg AS DECIMAL(12, 2))), 2) >= 80000
ORDER BY avg_salary DESC;
```

## Notes

- **Cast early, aggregate late:** Convert to `DECIMAL` before `AVG()`, `SUM()`, or multiplication; avoid mixing `FLOAT` in intermediate steps.
- **HAVING vs WHERE:** Filter on raw column with `WHERE`; use `HAVING` only after aggregation and rounding, or reuse the same `ROUND(AVG(...))` expression (or a CTE for clarity).
- **Banker's rounding trap:** PostgreSQL, SQL Server, and MySQL differ in their default rounding behavior; test your target database; explicitly use `ROUND(..., 2)` with mode parameter if available (e.g., PostgreSQL's `ROUND(x, 2)` defaults to banker's rounding).
- **Division order:** When computing per-unit rates (e.g., salary/12), cast numerator to `DECIMAL` and set sufficient scale to avoid truncation before rounding.
- **Reconciliation:** Always spot-check a few rows by hand and compare totals against business reports; precision bugs often hide in aggregations and are caught only through audit.
