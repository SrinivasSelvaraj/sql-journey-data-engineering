---
date: 2026-11-06
phase: sql
topic: Decimal precision: rounding modes and fixed-point arithmetic
---

# Decimal precision: rounding modes and fixed-point arithmetic

*SQL for analytics and engineering*

## Concept

Decimal precision and rounding modes determine how fractional values are stored and computed in analytics queries. SQL uses fixed-point arithmetic (DECIMAL/NUMERIC types) to avoid floating-point rounding errors that accumulate in financial calculations, percentages, and aggregations. Without explicit rounding mode specification, different databases apply different rules: ROUND_HALF_UP (common in PostgreSQL), ROUND_HALF_EVEN (banker's rounding in some systems), or truncation. This matters because a salary calculation off by 0.01 across millions of rows compounds into material errors in payroll, revenue reporting, and SLA metrics—and interviewers expect you to catch these edge cases.

When you aggregate salaries, compute commission percentages, or derive per-unit costs, you must choose your rounding mode deliberately. The default ROUND() function often rounds half-away-from-zero, but that's not universal. If you're calculating average salary to two decimal places for a report, you need to decide: do you round 123.456 to 123.46 (ROUND_HALF_UP) or 123.45 (truncate)? The choice affects downstream logic and reproducibility across systems.

## Practice

**Problem:** Calculate the average salary per job title, rounded to exactly 2 decimal places using ROUND_HALF_UP semantics. Return only titles where average salary exceeds $100,000. Ensure the result is consistent if the query runs on PostgreSQL or MySQL.

```sql
SELECT 
  job_title_short,
  ROUND(AVG(salary_year_avg)::NUMERIC, 2) AS avg_salary
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY job_title_short
HAVING ROUND(AVG(salary_year_avg)::NUMERIC, 2) > 100000.00
ORDER BY avg_salary DESC;
```

**Key moves:** Cast to NUMERIC (fixed-point) before rounding to prevent floating-point creep. Use ROUND(..., 2) with an explicit 2-digit precision. Apply the same ROUND logic in HAVING so filtering matches displayed values. Avoid rounding inside aggregate functions (use ROUND(AVG(...), 2), not AVG(ROUND(...))).

## Notes

- **Floating-point trap:** REAL and DOUBLE PRECISION types accumulate rounding errors; always use DECIMAL/NUMERIC for money, rates, and percentages.
- **Rounding in HAVING vs. SELECT:** If you filter on ROUND(...) > threshold in HAVING but don't round in SELECT, results look inconsistent. Apply rounding symmetrically.
- **Banker's rounding (ROUND_HALF_EVEN):** PostgreSQL uses it by default; MySQL rounds half-away-from-zero. Know your database's behavior or explicitly cast and test edge cases (e.g., 0.5, 1.5, 2.5).
- **Scale and precision:** DECIMAL(10, 2) means 10 total digits, 2 after the decimal. Ensure your column definitions match your calculation needs; truncation happens silently if scale is too small.
- **Adjacent: currency handling, tax calculations, partition window functions** where rounding must happen at the right step to avoid compounding errors.
