---
date: 2026-08-07
phase: sql
topic: Median and percentiles without built-ins
---

# Median and percentiles without built-ins

*SQL for analytics and engineering*

## Concept

Computing median and percentiles without built-in functions (like `PERCENTILE_CONT` or `PERCENTILE_DISC`) requires understanding row ordering and cumulative distribution. The core technique is ranking rows, calculating their position relative to total count, and selecting the value(s) that fall at your target percentile boundary. This matters because not all SQL dialects support percentile functions—older systems, some data warehouses, and interview contexts often expect manual implementation. Without the right approach, you either use expensive self-joins, compute wrong values by mishandling even vs. odd row counts, or fail to scale on large datasets.

The standard method uses `ROW_NUMBER()` or `RANK()` paired with `COUNT()` to find the position(s) matching your percentile. For the 50th percentile (median), you identify rows where their cumulative position equals or straddles the midpoint. The trickiest part: deciding whether to interpolate (average two middle values for even counts) or pick the lower/upper value, since this changes with `PERCENTILE_CONT` vs. `PERCENTILE_DISC` semantics.

## Practice

**Problem:** Find the median and 75th percentile of `salary_year_avg` across all job postings, handling ties and even row counts correctly.

```sql
WITH ranked_salaries AS (
  SELECT
    salary_year_avg,
    ROW_NUMBER() OVER (ORDER BY salary_year_avg) AS rn,
    COUNT(*) OVER () AS total_count
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
)
SELECT
  PERCENTILE_NAME,
  SALARY
FROM (
  -- Median (50th percentile, interpolated)
  SELECT
    '50th percentile (median)' AS PERCENTILE_NAME,
    AVG(salary_year_avg) AS SALARY
  FROM ranked_salaries
  WHERE rn IN (
    FLOOR((total_count + 1) / 2.0),
    CEIL((total_count + 1) / 2.0)
  )
  
  UNION ALL
  
  -- 75th percentile (discrete, upper value)
  SELECT
    '75th percentile' AS PERCENTILE_NAME,
    salary_year_avg AS SALARY
  FROM ranked_salaries
  WHERE rn = CEIL(0.75 * total_count)
) results;
```

This uses `ROW_NUMBER()` to assign sequential positions, `COUNT() OVER ()` for total rows, and conditional logic to pick the right row(s): for median, it averages the two middle values; for 75th, it takes the smallest row whose cumulative count reaches or exceeds 75% of the total.

## Notes

- **Even vs. odd counts:** Median of 4 values uses positions 2.5 (average positions 2 and 3); median of 5 uses position 3. Formula `(n+1)/2` handles this, but watch for integer vs. float division.
- **Null handling:** Always filter `WHERE column IS NOT NULL` before windowing, or null sorts unpredictably and breaks position math.
- **Discrete vs. continuous:** `PERCENTILE_DISC` (pick a real value) vs. `PERCENTILE_CONT` (interpolate). Most interviews expect discrete; interpolation requires `AVG()` on two neighbors.
- **Performance:** `ROW_NUMBER()` scales better than self-joins; avoid `CROSS JOIN` on full table. On huge datasets, pre-filter to relevant partition before ranking.
- **Connects to:** quantile regression, approximate percentiles (t-digest), histogram bucketing, and `NTILE()` for deciles/quartiles—often simpler if you just need 10 equal buckets rather than exact percentile values.
