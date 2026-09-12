---
date: 2026-09-12
phase: sql
topic: PIVOT and UNPIVOT: performance on sparse data
---

# PIVOT and UNPIVOT: performance on sparse data

*SQL for analytics and engineering*

## Concept

PIVOT and UNPIVOT transform row-oriented data into column-oriented format and vice versa. On sparse data—where most cell values are NULL—PIVOT operations can become expensive because the database must evaluate aggregation functions across every row combination, even when the result set is mostly empty. The performance cost scales with the cardinality of the pivot dimension and the number of rows that must be grouped and aggregated.

UNPIVOT is generally less problematic for performance, but on wide tables with hundreds of columns, materializing all columns into rows forces a cross join-like operation that can bloat intermediate results. The real danger with PIVOT on sparse data is unnecessary GROUP BY operations: if your fact table has 10M rows but only 50 unique values in the pivot column, you still scan and aggregate all 10M rows just to produce 50 output columns.

When sparse data PIVOT is necessary (e.g., building a feature matrix from events where most users don't have all event types), consider filtering before pivoting, pre-aggregating, or using conditional aggregation (SUM(CASE WHEN...)) instead. The last approach gives the query planner more visibility into which rows actually matter, avoiding full-table aggregations.

## Practice

**Problem:** You need to create a summary table showing average salary by job title, with one column per work-from-home status (remote vs. on-site). The job_postings_fact table has 500K rows but only 8 job titles and sparse remote work data (only 15% of postings are work-from-home). Write an efficient query.

```sql
-- Less efficient: PIVOT aggregates all 500K rows regardless of sparsity
SELECT *
FROM (
  SELECT job_title_short, job_work_from_home, salary_year_avg
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
)
PIVOT (
  AVG(salary_year_avg)
  FOR job_work_from_home IN (true AS remote, false AS on_site)
);

-- Better: conditional aggregation gives planner visibility
SELECT 
  job_title_short,
  AVG(CASE WHEN job_work_from_home = true THEN salary_year_avg END) AS remote_avg,
  AVG(CASE WHEN job_work_from_home = false THEN salary_year_avg END) AS on_site_avg
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY job_title_short;
```

## Notes

- **PIVOT hides the GROUP BY:** Some optimizers struggle to push predicates through PIVOT syntax; conditional aggregation (CASE + aggregate) is more transparent to cost-based planners.
- **Sparsity multiplier:** When pivoting on a column with *n* distinct values, you're creating *n* output columns but still scanning the full input table; sparse data amplifies waste because most output cells remain NULL.
- **UNPIVOT on wide tables:** If you have 200 columns and UNPIVOT into rows, expect a major cardinality explosion; filter column names or use dynamic SQL to materialize only relevant columns.
- **Intermediate materialization:** Both PIVOT and UNPIVOT force eager materialization in many SQL engines; CTEs or staging tables let you inspect the intermediate result and optimize earlier filtering.
- **Adjacent topic:** Learn window functions and CROSS JOIN for manual pivoting—often simpler and more controllable than PIVOT syntax, especially in interview settings where you must explain performance.
