---
date: 2026-08-07
phase: sql
topic: Conditional aggregation for pivoting
---

# Conditional aggregation for pivoting

*SQL for analytics and engineering*

## Concept

Conditional aggregation uses `CASE` expressions inside aggregate functions to selectively include or transform values before aggregation, enabling pivot-like reshaping without explicit `PIVOT` syntax. This technique is essential when you need to reorganize data by a dimension—for example, showing salary statistics broken out by work-from-home status in separate columns—without restructuring the underlying table.

The pattern is: `SUM(CASE WHEN condition THEN value ELSE 0 END)` or `COUNT(CASE WHEN condition THEN 1 END)`. It matters because it's portable across all SQL dialects (unlike `PIVOT` which is vendor-specific), performant when indexes align with `WHERE` clauses, and allows you to compute multiple aggregates in a single pass over the data. Without it, you'd resort to self-joins or subqueries per column, multiplying I/O and CPU cost.

What breaks without it: reporting queries become verbose and slow; you either write separate queries per dimension and join results (N+1 problem), or use expensive window functions and `DISTINCT` in ways that obscure intent and complicate the query planner's cost estimation.

## Practice

**Problem:** For each job title, show the count of total postings, the average salary for remote positions, and the average salary for non-remote positions. Return rows only where total postings ≥ 10.

```sql
SELECT
  job_title_short,
  COUNT(*) AS total_postings,
  ROUND(AVG(CASE WHEN job_work_from_home THEN salary_year_avg END), 0) AS avg_salary_remote,
  ROUND(AVG(CASE WHEN NOT job_work_from_home THEN salary_year_avg END), 0) AS avg_salary_onsite
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY job_title_short
HAVING COUNT(*) >= 10
ORDER BY total_postings DESC;
```

## Notes

- **NULL handling:** `AVG(CASE WHEN condition THEN value END)` automatically excludes NULLs from the denominator; use `COALESCE(…, 0)` or `SUM(…) / NULLIF(COUNT(CASE …), 0)` only if you need 0 for missing conditions.
- **Performance:** Conditional aggregation scans the table once; each `CASE` is evaluated at minimal cost. Verify with `EXPLAIN` that the planner doesn't materialize unnecessary intermediate tables.
- **Relation to window functions:** Don't confuse with `SUM() OVER (PARTITION BY …)`; conditional aggregation reduces rows via `GROUP BY`, while window functions preserve row count.
- **Common mistake:** Wrapping the entire `CASE` in `SUM()` or `COUNT()` instead of the condition inside—`SUM(CASE…)` not `SUM(x) CASE`—leads to syntax errors.
- **Adjacent skill:** Master this before tackling multi-level pivots (nested conditions) or dynamic column generation via string concatenation + `PREPARE` statements.
