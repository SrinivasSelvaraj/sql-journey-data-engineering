---
date: 2026-09-11
phase: sql
topic: HAVING vs WHERE: when aggregates filter correctly
---

# HAVING vs WHERE: when aggregates filter correctly

*SQL for analytics and engineering*

## Concept

**WHERE** filters *rows before aggregation*; **HAVING** filters *grouped results after aggregation*. This distinction is critical because aggregate functions (COUNT, SUM, AVG, MAX, MIN) only exist *after* the GROUP BY completes. If you write `WHERE COUNT(*) > 5`, SQL will reject it—COUNT doesn't exist yet. HAVING solves this by operating on the aggregated dataset.

The performance implication is significant: WHERE eliminates rows early, reducing the dataset before expensive grouping operations. HAVING must run after GROUP BY, so it cannot skip aggregation work. When you need to filter on an aggregate condition, HAVING is mandatory, but you should still use WHERE to pre-filter non-aggregate columns whenever possible—this is called "pushing predicates down."

A common mistake is forgetting that HAVING sees only grouped columns and aggregate functions. You cannot reference individual row values in HAVING (e.g., `HAVING job_location = 'New York'` will fail or behave unexpectedly if job_location isn't in GROUP BY). Any column-level filtering belongs in WHERE.

## Practice

**Problem:** Find all job titles that have been posted more than 50 times *and* where the average salary is above $100,000. Order by average salary descending.

```sql
SELECT
  job_title_short,
  COUNT(*) AS posting_count,
  AVG(salary_year_avg) AS avg_salary
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY job_title_short
HAVING COUNT(*) > 50
  AND AVG(salary_year_avg) > 100000
ORDER BY avg_salary DESC;
```

Note: `WHERE salary_year_avg IS NOT NULL` pre-filters rows before grouping (efficient); `HAVING COUNT(*) > 50` and `HAVING AVG(...) > 100000` filter groups after aggregation (required for aggregate conditions).

## Notes

- **Don't mix concerns:** WHERE on raw columns, HAVING on aggregates. Putting `job_location = 'Remote'` in HAVING instead of WHERE forces unnecessary grouping overhead.
- **Aggregate functions in HAVING only:** You can write aggregate expressions in HAVING that don't appear in SELECT (e.g., `HAVING COUNT(DISTINCT job_id) > 10`), giving you filtering flexibility beyond what you display.
- **NULL handling matters:** When filtering aggregates, remember that COUNT(*) includes NULLs but COUNT(column) does not. `HAVING COUNT(salary_year_avg) > 50` may differ from `HAVING COUNT(*) > 50` if salary is sparse.
- **Query plan implication:** Observing a FILTER (HAVING) step *after* GROUP BY in an execution plan is normal and expected. If HAVING appears before GROUP BY, that's a query planner optimization—trust it, but understand the logical order.
- **Adjacent topic:** FILTER clause in some databases (PostgreSQL, Snowflake) lets you compute conditional aggregates within SELECT, bypassing HAVING for certain patterns—worth exploring for advanced filtering scenarios.
