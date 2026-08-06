---
date: 2026-08-06
phase: sql
topic: GROUP BY, HAVING and the order of logical evaluation
---

# GROUP BY, HAVING and the order of logical evaluation

*SQL for analytics and engineering*

## Concept

`GROUP BY` partitions rows into groups based on column values, then aggregates each group independently. `HAVING` filters *groups* after aggregation, while `WHERE` filters *rows* before aggregation. The logical order is: FROM → WHERE → GROUP BY → aggregate functions → HAVING → ORDER BY. This ordering is critical because you cannot reference aggregate functions in WHERE (they don't exist yet), and you must understand which stage each filter operates at to write correct queries and reason about performance.

Without clear understanding of this order, queries fail or produce wrong results. For example, filtering `WHERE salary_year_avg > 100000` happens before grouping, so it excludes rows from consideration entirely; `HAVING AVG(salary_year_avg) > 100000` filters groups by their average salary after aggregation. Confusing these produces semantically different results and often causes runtime errors when you try to use unaggregated columns or aggregates in the wrong clause.

## Practice

**Problem:** Find job titles (excluding "Data Analyst") where the average salary across all postings for that title exceeds $120,000, and there are at least 50 postings. Order by average salary descending.

```sql
SELECT 
  job_title_short,
  COUNT(*) AS posting_count,
  AVG(salary_year_avg) AS avg_salary,
  ROUND(100.0 * SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_remote
FROM job_postings_fact
WHERE job_title_short != 'Data Analyst'
  AND salary_year_avg IS NOT NULL
GROUP BY job_title_short
HAVING COUNT(*) >= 50
  AND AVG(salary_year_avg) > 120000
ORDER BY avg_salary DESC;
```

## Notes

- **WHERE vs HAVING confusion:** WHERE runs row-by-row before grouping; HAVING runs group-by-group after aggregation. You cannot use aggregate functions in WHERE, and non-aggregated columns in HAVING are meaningless.
- **NULL handling:** Aggregate functions skip NULLs (COUNT excludes them unless you use COUNT(*)), and filtering NULLs in WHERE before grouping changes group membership and results.
- **Performance implication:** Filtering with WHERE before GROUP BY reduces rows entering the aggregation, often dramatically improving performance. Use WHERE aggressively for row-level conditions, HAVING only for aggregate-based filtering.
- **ORDER BY scope:** ORDER BY can reference both raw and aggregated columns, but typically uses aliases from SELECT to avoid re-computing expressions.
- **Adjacent concepts:** Window functions (OVER clause) operate *after* GROUP BY and don't partition data like GROUP BY does; they're orthogonal and solve different problems (ranking within groups vs. aggregating groups).
