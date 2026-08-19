---
date: 2026-08-19
phase: sql
topic: GROUPING SETS, CUBE and ROLLUP
---

# GROUPING SETS, CUBE and ROLLUP

*SQL for analytics and engineering*

## Concept

GROUPING SETS, CUBE, and ROLLUP are SQL extensions that generate multiple aggregation levels in a single query without needing UNION ALL. They're essential when you need subtotals, grand totals, and dimensional summaries simultaneously—common in analytics dashboards and reporting pipelines.

**ROLLUP(A, B, C)** creates a hierarchical aggregation: (A, B, C) → (A, B) → (A) → (). It answers "total by A and B, then by A alone, then overall." **CUBE(A, B, C)** generates *all* possible combinations of dimensions, useful when you don't know the query direction in advance. **GROUPING SETS** gives you explicit control: you specify exactly which dimension combinations to aggregate.

Without these, you'd chain multiple GROUP BY queries with UNION ALL, creating redundant table scans, harder-to-read code, and performance bottlenecks. The optimizer can often execute these as a single pass, making them dramatically faster for large fact tables.

## Practice

**Problem:** Generate a report showing average salary by job title, by work-from-home status, by both dimensions together, and a grand total—all in one query result.

```sql
SELECT
  job_title_short,
  job_work_from_home,
  COUNT(*) as job_count,
  ROUND(AVG(salary_year_avg), 0) as avg_salary,
  GROUPING(job_title_short) as is_title_total,
  GROUPING(job_work_from_home) as is_wfh_total
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY GROUPING SETS (
  (job_title_short, job_work_from_home),
  (job_title_short),
  (job_work_from_home),
  ()
)
ORDER BY
  GROUPING(job_title_short),
  GROUPING(job_work_from_home),
  job_title_short,
  job_work_from_home;
```

The GROUPING() function returns 1 when a dimension is aggregated (part of the total), 0 when it's a real value—essential for labeling rows correctly in downstream reporting.

## Notes

- **GROUPING() is mandatory for interpretation**: Without it, NULL in a grouping column is indistinguishable from actual NULL data. Always include GROUPING flags in SELECT.
- **CUBE explodes cardinality**: CUBE(A, B, C) generates 2³=8 result sets. On high-dimensional data, this can create massive output; use explicit GROUPING SETS instead.
- **Optimizer matters**: Postgres and newer SQL Server versions handle these efficiently as single-pass operations; older systems may materialize intermediate results. Check EXPLAIN output.
- **Adjacent concept—window functions**: ROLLUP + window functions (ROW_NUMBER() OVER (PARTITION BY ...)) let you mark subtotal rows and rank within groups simultaneously.
- **ROLLUP order is significant**: ROLLUP(A, B, C) ≠ ROLLUP(B, A, C). The hierarchy flows left-to-right; choose your dimension order carefully based on how users will filter/drill.
