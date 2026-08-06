---
date: 2026-08-06
phase: sql
topic: Self joins and hierarchical lookups
---

# Self joins and hierarchical lookups

*SQL for analytics and engineering*

## Concept

A self join occurs when a table references itself to compare rows or traverse hierarchical relationships. This is essential for finding peer comparisons (e.g., jobs at the same salary level), detecting duplicates, or walking parent-child structures (like manager-employee chains). Without self joins, you cannot express "find jobs paying within 10% of this job" or "show me all reporting levels in an org chart" without expensive application-side logic.

Self joins become critical in analytics when your data is denormalized into a single table but contains implicit relationships. The key challenge is aliasing the same table twice (or more) with different logical roles, then joining on the appropriate key. Query planner behavior matters here—poor join conditions can trigger cartesian products or inefficient nested loops on large tables.

In interviews, self joins test whether you can model relationships abstractly and write joins that are both logically correct and performant. They often appear alongside window functions as alternative approaches; knowing when self join beats window function (or vice versa) demonstrates maturity.

## Practice

**Problem:** Find all job postings that are similar to job_id 12345, defined as having the same job_title_short and a salary within ±15% of the target job. Return the similar job's id, title, salary, and the salary difference.

```sql
SELECT
  j2.job_id,
  j2.job_title_short,
  j2.salary_year_avg,
  j2.salary_year_avg - j1.salary_year_avg AS salary_diff
FROM job_postings_fact j1
INNER JOIN job_postings_fact j2
  ON j1.job_title_short = j2.job_title_short
  AND j2.salary_year_avg BETWEEN j1.salary_year_avg * 0.85 AND j1.salary_year_avg * 1.15
WHERE j1.job_id = 12345
  AND j2.job_id != j1.job_id
ORDER BY salary_diff;
```

## Notes

- **Self-join trap:** forgetting the inequality condition (e.g., `j2.job_id != j1.job_id`) leads to the row matching itself; always exclude self-matches unless self-comparison is the goal.
- **Index and cardinality:** self joins on non-indexed columns or low-cardinality fields (like job_title_short) can explode result sets; check EXPLAIN PLAN and consider whether a GROUP BY or window function is cheaper.
- **Aliasing discipline:** use clear, consistent aliases (j1 = reference row, j2 = comparison row) to avoid confusion in multi-level joins or when three+ copies of the same table appear.
- **Window function alternative:** `ROW_NUMBER() OVER (PARTITION BY job_title_short ORDER BY salary_year_avg)` can replace some self joins for ranking/peer tasks; self joins are better for cross-record comparisons, window functions for within-group positioning.
- **Revisit:** hierarchical CTEs (recursive WITH clauses) extend self-join logic to arbitrary tree depths; practice those after mastering flat self joins.
