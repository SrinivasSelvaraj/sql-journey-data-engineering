---
date: 2026-09-12
phase: sql
topic: CASE expression short-circuit evaluation and side effects
---

# CASE expression short-circuit evaluation and side effects

*SQL for analytics and engineering*

## Concept

SQL `CASE` expressions do **not** guarantee short-circuit evaluation across all databases. Unlike programming languages, SQL engines may evaluate all branches of a `CASE` statement before determining which one applies. This means if you write `CASE WHEN column / 0 = 1 THEN ... END`, the division-by-zero error can still occur even in the `THEN` clause that never executes, depending on the optimizer.

Short-circuit evaluation matters most when you're trying to guard against invalid operations: dividing by zero, casting incompatible types, regex matching on null, or calling functions with preconditions. In PostgreSQL and some others, `CASE` *does* respect evaluation order, but in systems like SQL Server or Snowflake, the optimizer may reorder or parallelize branch evaluation. Always assume branches execute unless documented otherwise.

Without understanding this, you'll write defensive code that appears correct locally but fails in production under different query plans or on different databases. The fix is structural: use `WHERE` filters, `JOINs`, and `NULLIF()` to prevent invalid inputs from reaching risky operations, rather than relying on `CASE` logic alone.

## Practice

**Problem:** You need to calculate average salary by job location, but salary data is sometimes 0 or null. You want to flag records where salary exists and calculate a safety metric: salary divided by years of experience (estimated from job posting age). However, some jobs have incomplete data. Write a query that safely computes `salary_year_avg / experience_estimate` without division-by-zero errors, and returns null if any denominator is invalid.

```sql
SELECT
  job_location,
  COUNT(*) as job_count,
  AVG(salary_year_avg) as avg_salary,
  AVG(
    CASE
      WHEN salary_year_avg > 0
        AND EXTRACT(YEAR FROM CURRENT_DATE) - EXTRACT(YEAR FROM job_posted_date) > 0
      THEN salary_year_avg / (EXTRACT(YEAR FROM CURRENT_DATE) - EXTRACT(YEAR FROM job_posted_date))
      ELSE NULL
    END
  ) as avg_salary_per_year_experience
FROM job_postings_fact
WHERE job_posted_date IS NOT NULL
GROUP BY job_location
ORDER BY avg_salary DESC;
```

**Key moves:** (1) Pre-filter with `WHERE` to eliminate null dates. (2) Use `AND` in the `WHEN` clause to ensure *both* divisor conditions are true before division. (3) Return `NULL` rather than a fallback value—this signals missing/invalid data and won't skew aggregates.

## Notes

- **CASE is not a safety mechanism**—it's a labeling tool. Filtering and `NULLIF()` are your real guards against errors; place them *before* CASE when possible.
- **Database-specific behavior**: Test on your target system. PostgreSQL, MySQL, and recent Snowflake tend to short-circuit; SQL Server and older systems may not. Assume worst case.
- **Aggregate functions ignore NULL**: `AVG()`, `SUM()`, and `COUNT()` skip null values by design—use this to your advantage instead of padding with zeros or flags inside CASE.
- **Related: `NULLIF(denominator, 0)` as alternative**—often cleaner than CASE for simple guard logic; `AVG(salary / NULLIF(experience, 0))` is more readable than nested CASE.
- **Query plan inspection**: Use `EXPLAIN` to verify the optimizer isn't evaluating both branches in parallel; if you see warnings or redundant scans, restructure with explicit `WHERE` or derived tables.
