---
date: 2026-08-25
phase: sql
topic: Grouping sets, cube and rollup for multi-dimensional aggregates
---

# Grouping sets, cube and rollup for multi-dimensional aggregates

*SQL for analytics and engineering*

## Concept

**GROUPING SETS, CUBE, and ROLLUP** are SQL extensions that generate multiple levels of aggregation in a single query. Without them, you'd need separate queries UNIONed together—slow, verbose, and error-prone. `GROUPING SETS` lets you specify exactly which dimension combinations you want; `CUBE` generates *all* possible combinations; `ROLLUP` generates a hierarchy (e.g., year → quarter → month → detail).

These matter most in analytics dashboards, data warehouses, and reports where you need subtotals and grand totals. They're performant because the database optimizes a single pass over sorted data rather than multiple table scans. Without them, you either write 5–10 UNION queries (maintainability nightmare) or accept incomplete aggregations.

The critical distinction: `ROLLUP(A, B, C)` respects order and produces 4 result sets (ABC, AB, A, total); `CUBE(A, B, C)` produces 8 (all subsets); `GROUPING SETS((A,B), (B,C), ())` produces exactly what you specify. Misunderstanding the difference leads to either redundant data or missing rollup levels.

## Practice

**Problem:** A recruitment analytics team needs a single query that shows:
- Average salary by job title and work-from-home status
- Average salary by job title only (subtotal)
- Average salary by work-from-home status only (subtotal)
- Overall average salary (grand total)

```sql
SELECT
  job_title_short,
  job_work_from_home,
  ROUND(AVG(salary_year_avg), 0) AS avg_salary,
  COUNT(*) AS job_count,
  GROUPING(job_title_short) AS title_is_null,
  GROUPING(job_work_from_home) AS wfh_is_null
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY GROUPING SETS (
  (job_title_short, job_work_from_home),
  (job_title_short),
  (job_work_from_home),
  ()
)
ORDER BY
  job_title_short NULLS LAST,
  job_work_from_home NULLS LAST;
```

The `GROUPING()` function returns 1 when a column is aggregated (NULL in output), 0 when it's part of the grouping key—useful for filtering or labeling rollup rows in reports.

## Notes

- **GROUPING function is mandatory for identification:** NULLs in your data are ambiguous from aggregate NULLs. Always use `GROUPING()` to distinguish "this dimension was rolled up" from "this column value is actually NULL."
- **Performance scales with cardinality:** CUBE can explode memory usage if dimensions have high cardinality (e.g., `CUBE(user_id, timestamp)` generates millions of groups). Use GROUPING SETS to pick only the combinations you need.
- **Order matters in ROLLUP:** `ROLLUP(date, region, product)` produces hierarchical rollups; swapping to `ROLLUP(product, region, date)` changes which subtotals appear. Document the intent clearly.
- **UNION ALL alternative is always there:** Some teams prefer explicit UNIONs for readability or when different dimensions need different filters. Benchmark—GROUPING SETS isn't always faster on every database engine.
- **Adjacent skills:** Window functions (LAG/LEAD) pair well for comparing each row to its parent rollup level; materialized views often cache CUBE results; understand your query planner's handling of `GROUP BY` cardinality estimation.
