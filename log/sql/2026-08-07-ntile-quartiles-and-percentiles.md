---
date: 2026-08-07
phase: sql
topic: NTILE, quartiles and percentiles
---

# NTILE, quartiles and percentiles

*SQL for analytics and engineering*

## Concept

NTILE divides rows into N equal-sized buckets based on a sorted order, assigning each row a bucket number from 1 to N. Quartiles (NTILE with N=4) and percentiles (NTILE with N=100) are the most common applications—they let you segment data into meaningful distribution bands without hardcoding threshold values. This matters in analytics when you need to classify salary ranges, performance tiers, or engagement levels in a way that adapts to your actual data rather than arbitrary cutoffs.

Without NTILE, you'd either manually calculate percentiles using window functions like ROW_NUMBER and COUNT(*), or hardcode thresholds that break when data changes. NTILE handles skewed distributions gracefully: if you have 1000 rows, NTILE(4) creates four groups as close to 250 as possible, rather than requiring you to compute exact boundary values. It's a declarative way to express "split this data into equal groups by rank."

The key difference from PERCENT_RANK or CUME_DIST is that NTILE assigns discrete bucket numbers, while those functions return fractional ranks. Use NTILE when you want to partition and aggregate by group; use PERCENT_RANK when you want each row's exact percentile position as a 0–1 value.

## Practice

**Problem:** Segment data engineer job postings into salary quartiles. For each quartile, show the salary range (min and max) and count of postings. Include only jobs with a non-null average salary and remote work capability.

```sql
WITH salary_tiers AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    NTILE(4) OVER (ORDER BY salary_year_avg) AS quartile
  FROM job_postings_fact
  WHERE job_title_short = 'Data Engineer'
    AND salary_year_avg IS NOT NULL
    AND job_work_from_home = TRUE
)
SELECT
  quartile,
  COUNT(*) AS posting_count,
  MIN(salary_year_avg) AS min_salary,
  MAX(salary_year_avg) AS max_salary,
  ROUND(AVG(salary_year_avg), 0) AS avg_salary
FROM salary_tiers
GROUP BY quartile
ORDER BY quartile;
```

## Notes

- **Off-by-one thinking:** NTILE returns 1-indexed buckets (1, 2, 3, 4), not 0-indexed. Bucket 1 is always the lowest; bucket N is always the highest after ORDER BY.
- **Unequal group sizes:** When row count isn't divisible by N, NTILE distributes remainder rows to lower-numbered buckets first. Document this behavior in comments if stakeholders expect perfectly equal counts.
- **ORDER BY is required:** NTILE is meaningless without a clear sort order. Missing ORDER BY will either error or produce nonsensical results depending on your database.
- **Bridges to percentile_cont/percentile_disc:** When you need exact percentile values (e.g., "75th percentile salary = $X") rather than bucket assignment, use PERCENTILE_CONT or PERCENTILE_DISC instead; they're often more efficient for single-point calculations.
- **Performance consideration:** NTILE scans the full result set to assign buckets, so filtering with WHERE before the window function keeps cardinality low and query fast.
