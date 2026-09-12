---
date: 2026-09-12
phase: sql
topic: NULL ordering and sparse index utilization
---

# NULL ordering and sparse index utilization

*SQL for analytics and engineering*

## Concept

NULL ordering determines where NULL values appear in sorted result sets—typically at the beginning (NULLS FIRST) or end (NULLS LAST) depending on the database and sort direction. This matters because filtering and ranking logic often depends on predictable NULL placement; a salary comparison that doesn't explicitly handle NULLs can incorrectly exclude remote positions or inflate average calculations. Sparse indexes (indexes on columns with many NULLs) are underutilized by query planners when NULL handling is implicit, because most databases don't index NULLs by default. Without explicit NULL ordering, you lose both correctness in analytics (wrong aggregates) and performance (index scans instead of seeks on nullable columns).

## Practice

**Problem:** Rank job postings by salary within each job title, but remote-work positions often have NULL salaries. You need to rank them last within each title group, ensure remote workers (job_work_from_home = true) with NULL salary appear below all paid roles, and identify the top 3 salary tiers per title efficiently.

```sql
SELECT
  job_title_short,
  job_id,
  salary_year_avg,
  job_work_from_home,
  ROW_NUMBER() OVER (
    PARTITION BY job_title_short 
    ORDER BY salary_year_avg DESC NULLS LAST, job_work_from_home ASC
  ) AS salary_rank
FROM job_postings_fact
WHERE job_posted_date >= '2024-01-01'
  AND (salary_year_avg IS NOT NULL OR job_work_from_home = true)
QUALIFY salary_rank <= 3
ORDER BY job_title_short, salary_rank;
```

Key points: `NULLS LAST` ensures unpaid/remote roles rank lower; the `QUALIFY` clause filters within the window (more efficient than a subquery); the WHERE clause preserves remote positions even without salary data.

## Notes

- **Database-specific syntax:** PostgreSQL uses `NULLS LAST/FIRST` in ORDER BY; MySQL and SQLite require `CASE WHEN ... IS NULL` workarounds; BigQuery and Snowflake support the standard syntax natively.
- **Sparse index myth:** Most query planners skip indexes on nullable columns unless you explicitly filter `WHERE col IS NOT NULL`; combine index hints with NULL ordering for predictable performance on sparse data.
- **Window function gotcha:** NULLS LAST placement in OVER clauses sometimes doesn't push down to the engine optimizer—test execution plans to confirm index usage.
- **Aggregation pitfall:** `AVG(salary)` silently ignores NULLs, which can hide data quality issues; pair NULL handling in ORDER BY with explicit counts (`COUNT(*) vs COUNT(salary)`) in analytics.
- **Adjacent topic:** Composite indexes benefit from NULL ordering strategy; a filtered index (`WHERE col IS NOT NULL`) can outperform sparse index + NULL handling, depending on selectivity.
