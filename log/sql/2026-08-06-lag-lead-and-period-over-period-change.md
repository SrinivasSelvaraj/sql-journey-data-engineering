---
date: 2026-08-06
phase: sql
topic: LAG, LEAD and period-over-period change
---

# LAG, LEAD and period-over-period change

*SQL for analytics and engineering*

## Concept

LAG and LEAD are window functions that retrieve values from preceding or following rows within a partition, without requiring a self-join. They are essential for computing period-over-period changes (month-over-month salary trends, day-over-day posting volume), detecting anomalies, and building sequences. Without them, you'd need expensive self-joins or application-layer logic.

The key syntax is `LAG(column, offset, default) OVER (PARTITION BY ... ORDER BY ...)` and `LEAD(column, offset, default) OVER (...)`. The offset (default 1) specifies how many rows back/forward to look; the default value handles edge cases where no row exists. The ORDER BY clause is mandatory—it defines what "previous" and "next" mean.

Period-over-period analysis becomes straightforward: calculate `current_value - LAG(current_value) OVER (...)` to measure change. This pattern is foundational for retention cohorts, revenue tracking, and detecting data quality issues (e.g., a salary jump).

## Practice

**Problem:** For each job_title_short, compute the month-over-month change in average salary. Show the job title, year-month, average salary, prior month's average salary, and the absolute change. Order by title and date.

```sql
WITH monthly_avg AS (
  SELECT 
    job_title_short,
    DATE_TRUNC('month', job_posted_date)::DATE AS month,
    ROUND(AVG(salary_year_avg)::NUMERIC, 2) AS avg_salary
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
  GROUP BY job_title_short, DATE_TRUNC('month', job_posted_date)
)
SELECT 
  job_title_short,
  month,
  avg_salary,
  LAG(avg_salary) OVER (PARTITION BY job_title_short ORDER BY month) AS prior_month_salary,
  ROUND((avg_salary - LAG(avg_salary) OVER (PARTITION BY job_title_short ORDER BY month))::NUMERIC, 2) AS mom_change
FROM monthly_avg
ORDER BY job_title_short, month;
```

## Notes

- **Partition boundaries matter:** LAG/LEAD return NULL at partition edges unless you specify a default. Use `COALESCE(LAG(...), avg_salary) OVER (...)` to handle first rows gracefully.
- **ORDER BY is non-negotiable:** Without it, row order is undefined and results are unpredictable. Always define sort order explicitly in the OVER clause.
- **Offset and default parameters are optional but useful:** `LAG(salary, 3, 0)` retrieves the salary from 3 rows back, defaulting to 0 if unavailable—saves a CASE statement.
- **Connects to:** ROW_NUMBER, RANK, DENSE_RANK (other window functions), self-joins (the anti-pattern it replaces), and running aggregates like SUM() OVER (...).
- **Performance consideration:** Window functions are generally more efficient than self-joins in modern databases, but always review the query plan to confirm index usage on ORDER BY columns.
