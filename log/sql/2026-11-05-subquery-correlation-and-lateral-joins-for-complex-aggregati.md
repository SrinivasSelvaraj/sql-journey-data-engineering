---
date: 2026-11-05
phase: sql
topic: Subquery correlation and lateral joins for complex aggregations
---

# Subquery correlation and lateral joins for complex aggregations

*SQL for analytics and engineering*

## Concept

A **correlated subquery** executes once per outer row, with the inner query referencing columns from the outer context. A **lateral join** (available in PostgreSQL, Snowflake, BigQuery AS) achieves similar results but treats the right side as a derived table that can reference the left, executing row-by-row with better optimizer visibility. Both solve the same problem: computing row-specific aggregations or rankings without window functions—critical when you need *filtered* aggregates (e.g., "average salary for roles posted after this job's date") rather than full-partition aggregates.

Correlated subqueries are intuitive but often perform poorly because the optimizer may not recognize they're deterministic and can be rewritten. Lateral joins make the row-by-row dependency explicit and give modern query planners better hooks for optimization. Without these patterns, you're forced into clunky workarounds: full outer joins with filtering, temporary tables, or incorrect window functions that compute over the wrong partition.

The performance difference matters at scale. A naive correlated subquery on a 1M-row table can trigger 1M inner scans. A lateral join or properly rewritten subquery can be optimized into a single sort-merge or hash join, running orders of magnitude faster.

## Practice

**Problem:** For each job posting, find the count of other postings in the same location posted within 30 days *after* it, and the average salary of those future postings.

```sql
-- Using LATERAL (PostgreSQL/Snowflake/BigQuery syntax shown for Postgres)
SELECT 
  jp1.job_id,
  jp1.job_title_short,
  jp1.job_location,
  jp1.job_posted_date,
  future_stats.future_count,
  future_stats.future_avg_salary
FROM job_postings_fact jp1
LATERAL (
  SELECT 
    COUNT(*) AS future_count,
    AVG(salary_year_avg) AS future_avg_salary
  FROM job_postings_fact jp2
  WHERE jp2.job_location = jp1.job_location
    AND jp2.job_posted_date > jp1.job_posted_date
    AND jp2.job_posted_date <= jp1.job_posted_date + INTERVAL '30 days'
) AS future_stats
ORDER BY jp1.job_posted_date;

-- Equivalent correlated subquery (less efficient in most planners)
SELECT 
  jp1.job_id,
  jp1.job_title_short,
  jp1.job_location,
  jp1.job_posted_date,
  (SELECT COUNT(*) FROM job_postings_fact jp2
   WHERE jp2.job_location = jp1.job_location
     AND jp2.job_posted_date > jp1.job_posted_date
     AND jp2.job_posted_date <= jp1.job_posted_date + INTERVAL '30 days') AS future_count,
  (SELECT AVG(salary_year_avg) FROM job_postings_fact jp2
   WHERE jp2.job_location = jp1.job_location
     AND jp2.job_posted_date > jp1.job_posted_date
     AND jp2.job_posted_date <= jp1.job_posted_date + INTERVAL '30 days') AS future_avg_salary
FROM job_postings_fact jp1
ORDER BY jp1.job_posted_date;
```

## Notes

- **Lateral is declaratively clearer**: one subquery object vs. duplicated WHERE logic across multiple scalar subqueries; planners also see it as a single join operation, not independent scans.
- **Avoid repeated subqueries**: if you call the same correlated subquery twice, you execute twice—use LATERAL to compute once and reference multiple columns.
- **Window functions are not a replacement**: `ROW_NUMBER() OVER (PARTITION BY location ORDER BY posted_date)` ranks *all* future rows; correlated/lateral queries *filter* within a range, solving a different problem.
- **Indexes matter**: both patterns benefit hugely from indexes on (location, posted_date) to prune the inner scan; without them, you're still doing table scans per outer row.
- **BigQuery tip**: use `ARRAY(SELECT ...)` or explicit CROSS JOIN UNNEST for lateral-like behavior; standard correlated subqueries work but are slower than explicit joins with LEFT OUTER JOIN + GROUP BY.
