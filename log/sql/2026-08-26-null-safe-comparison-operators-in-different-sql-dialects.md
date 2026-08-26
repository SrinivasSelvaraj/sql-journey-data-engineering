---
date: 2026-08-26
phase: sql
topic: Null-safe comparison operators in different SQL dialects
---

# Null-safe comparison operators in different SQL dialects

*SQL for analytics and engineering*

## Concept

Standard SQL comparison operators (`=`, `!=`, `<>`) treat `NULL` as unknown, meaning `NULL = NULL` returns unknown (not true), and any comparison with `NULL` returns unknown. This causes rows with `NULL` values to be silently excluded from results, leading to incomplete datasets and hard-to-debug analytics queries. The `IS NULL` and `IS NOT NULL` operators exist precisely because `NULL` cannot be compared using standard operators.

Different SQL dialects offer null-safe comparison operators to make this easier: PostgreSQL and some others support `IS DISTINCT FROM` / `IS NOT DISTINCT FROM`, while MySQL and SQLite use the `<=>` operator. BigQuery, Snowflake, and others support `IS DISTINCT FROM`. Using these operators eliminates the need for defensive `OR col IS NULL` clauses and makes comparisons between nullable columns reliable without verbose logic.

Without null-safe operators, queries checking equality between two columns containing nulls will miss matching rows where both sides are `NULL`. This is especially dangerous in joins and filters where you expect symmetry: `WHERE salary_year_avg = previous_salary_year_avg` will exclude records where both are `NULL`, potentially undercounting matches.

## Practice

**Problem:** You need to identify job postings where the work-from-home status matches the previous posting for the same company. Using standard operators, rows where *both* postings have `NULL` work_from_home values are excluded. Write a query that correctly includes all matching cases, including when both values are `NULL`.

```sql
-- Using IS NOT DISTINCT FROM (PostgreSQL, BigQuery, Snowflake, Redshift)
SELECT 
  current.job_id,
  current.job_title_short,
  previous.job_id AS previous_job_id
FROM job_postings_fact AS current
JOIN job_postings_fact AS previous
  ON current.job_location = previous.job_location
  AND current.job_posted_date > previous.job_posted_date
  AND current.job_work_from_home IS NOT DISTINCT FROM previous.job_work_from_home
WHERE current.job_title_short = previous.job_title_short;

-- Alternative for MySQL / SQLite using <=>
SELECT 
  current.job_id,
  current.job_title_short,
  previous.job_id AS previous_job_id
FROM job_postings_fact AS current
JOIN job_postings_fact AS previous
  ON current.job_location = previous.job_location
  AND current.job_posted_date > previous.job_posted_date
  AND current.job_work_from_home <=> previous.job_work_from_home
WHERE current.job_title_short = previous.job_title_short;

-- Fallback without null-safe operator (verbose, error-prone)
SELECT 
  current.job_id,
  current.job_title_short,
  previous.job_id AS previous_job_id
FROM job_postings_fact AS current
JOIN job_postings_fact AS previous
  ON current.job_location = previous.job_location
  AND current.job_posted_date > previous.job_posted_date
  AND (current.job_work_from_home = previous.job_work_from_home 
       OR (current.job_work_from_home IS NULL AND previous.job_work_from_home IS NULL))
WHERE current.job_title_short = previous.job_title_short;
```

## Notes

- **Dialect awareness in interviews:** Always clarify which database you're using. Mention null-safe operators early if the problem involves nullable columns in joins or filters—it signals you understand NULL semantics.
- **Common mistake:** Writing `WHERE col1 = col2` in a self-join or comparison context and not realizing `NULL` rows are silently dropped. Always think: "What if both sides are NULL?"
- **Adjacent topics:** Three-valued logic (TRUE, FALSE, UNKNOWN), `COALESCE()` for NULL replacement, handling `NULL` in aggregates (`COUNT(*)` vs `COUNT(col)`), and proper join conditions.
- **Performance note:** `IS NOT DISTINCT FROM` and `<=>` are standard comparison operations in most modern engines and incur negligible overhead vs. standard operators—use them freely.
- **Revisit:** Practice writing join conditions on multiple nullable columns and trace through which rows pass/fail the filter to build intuition around NULL propagation.
