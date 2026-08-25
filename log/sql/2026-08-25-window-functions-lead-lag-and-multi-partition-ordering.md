---
date: 2026-08-25
phase: sql
topic: Window functions: LEAD, LAG and multi-partition ordering
---

# Window functions: LEAD, LAG and multi-partition ordering

*SQL for analytics and engineering*

## Concept

Window functions like `LEAD()` and `LAG()` allow you to access data from other rows in a result set without requiring a self-join. `LAG(column, offset, default)` retrieves values from a preceding row; `LEAD(column, offset, default)` retrieves from a following row. The offset (default 1) and default value are optional. Critically, window functions operate *after* the WHERE clause, so they see the filtered result set and can reference any column in the SELECT statement.

Multi-partition ordering means you can divide your result set into independent groups (PARTITION BY) and apply LAG/LEAD *within each partition separately*. Without partitioning, LAG/LEAD cross group boundaries, which is almost always wrong for time-series analysis. For example, if you partition by `user_id` and order by `date`, you can safely compare each user's salary changes without accidentally comparing one user's data to another's.

This matters in analytics because salary progression, login streaks, price changes, and retention analysis all require comparing consecutive events within logical groups. Without window functions, you'd need expensive self-joins or application-side logic; with them, the database handles the ordering efficiently, and query planners can optimize partition-wise execution.

## Practice

**Problem:** For each job location, identify job postings and calculate the salary difference between each posting and the previous posting (in that location, ordered by date). Include the previous posting's date. Return only postings where the salary difference is greater than $20,000 (to find salary jumps).

```sql
WITH salary_changes AS (
  SELECT
    job_location,
    job_posted_date,
    job_title_short,
    salary_year_avg,
    LAG(salary_year_avg) OVER (
      PARTITION BY job_location 
      ORDER BY job_posted_date
    ) AS prev_salary,
    LAG(job_posted_date) OVER (
      PARTITION BY job_location 
      ORDER BY job_posted_date
    ) AS prev_posted_date,
    salary_year_avg - LAG(salary_year_avg) OVER (
      PARTITION BY job_location 
      ORDER BY job_posted_date
    ) AS salary_diff
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
)
SELECT
  job_location,
  prev_posted_date,
  job_posted_date,
  job_title_short,
  prev_salary,
  salary_year_avg,
  salary_diff
FROM salary_changes
WHERE salary_diff > 20000
ORDER BY job_location, job_posted_date;
```

## Notes

- **Partition order matters:** Always verify your PARTITION BY and ORDER BY clauses match the business logic. Wrong partitioning silently produces garbage (comparing across groups); wrong ordering gives you the "wrong previous row."
- **NULL handling:** LAG/LEAD return NULL for rows with no preceding/following row. Use the third argument as a default, or filter with `WHERE prev_salary IS NOT NULL` if you only want rows with a valid comparison.
- **Performance consideration:** Window functions can't always push predicates down; avoid filtering on window function results in WHERE—use a CTE or subquery and filter the result.
- **Adjacent topics:** Row numbering (ROW_NUMBER, RANK, DENSE_RANK), running aggregates (SUM/AVG OVER), and frame specifications (ROWS BETWEEN) are natural extensions that use the same OVER() syntax.
- **Revisit:** Test edge cases—what happens with NULL salaries, gaps in dates within a partition, and ties in the ORDER BY clause (use a tiebreaker like job_id if determinism matters).
