---
date: 2026-10-23
phase: sql
topic: NULL handling in joins and aggregations
---

# NULL handling in joins and aggregations

*SQL for analytics and engineering*

## Concept

NULLs behave distinctly in SQL joins and aggregations—they do not match anything, not even other NULLs. In a LEFT or INNER JOIN, rows with NULL foreign keys will not join to anything; in a RIGHT or FULL OUTER JOIN, you'll get rows with all NULLs on one side. This creates silent data loss: a query may return fewer rows than expected without error. In aggregations (COUNT, SUM, AVG), NULLs are skipped entirely—COUNT(*) includes them, but COUNT(column_name) excludes them. Without deliberate NULL handling, joins drop rows and aggregates undercount, making dashboards and analytics unreliable.

The risk is highest in fact tables with optional relationships (e.g., a job posting without a salary, or without a location assignment) and in multi-stage pipelines where NULL propagates downstream undetected. A single LEFT JOIN against a table with NULL keys can lose 20–30% of records without raising an exception.

## Practice

**Problem:** Write a query that counts job postings by work-from-home status and returns the average salary for each group. Handle the case where job_work_from_home is NULL (treat it as "Unknown") and exclude salary NULLs from the average but keep rows with NULL salary in the group count.

```sql
SELECT 
  COALESCE(job_work_from_home::TEXT, 'Unknown') AS work_from_home_status,
  COUNT(*) AS total_postings,
  COUNT(salary_year_avg) AS postings_with_salary,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary
FROM job_postings_fact
GROUP BY COALESCE(job_work_from_home::TEXT, 'Unknown')
ORDER BY total_postings DESC;
```

This uses COALESCE to treat NULL work_from_home as a visible group, COUNT(*) to include all rows in each group, and COUNT(salary_year_avg) to show how many have non-NULL salary (aggregates naturally skip NULLs). AVG skips NULLs automatically.

## Notes

- **COUNT(*) vs COUNT(col):** Always clarify intent—COUNT(*) includes NULLs, COUNT(col) excludes them. This is the #1 source of "missing rows" bugs.
- **JOIN NULL keys are silent:** A job_posting with NULL location will not match any location_dim row, even if location_id is also NULL there. Use COALESCE or CASE to handle missing keys before joining, or use LEFT JOIN + IS NULL filters to detect unmatchable rows.
- **Aggregation without GROUP BY:** If you GROUP BY a column with NULLs, they form their own group. This is correct behavior but easy to miss in result validation.
- **Adjacent topics:** CASE WHEN for conditional NULL replacement, window functions (which also skip NULLs in aggregates), and three-valued logic (TRUE, FALSE, NULL in WHERE clauses—WHERE NULL is always false, filtering out unknowns).
- **Revisit:** Practice writing explicit NULL handling logic (COALESCE, CASE, IFNULL) and inspecting query plans to see if joins are filtering as expected; use CROSS JOIN or FULL OUTER JOIN tests to verify NULL behavior assumptions.
