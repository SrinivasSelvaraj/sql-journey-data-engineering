---
date: 2026-10-03
phase: sql
topic: Window function optimization: frame specification impact
---

# Window function optimization: frame specification impact

*SQL for analytics and engineering*

## Concept

Window function frame specification determines which rows are included in the calculation for each row—ROWS vs RANGE, and the boundary clauses (UNBOUNDED PRECEDING, CURRENT ROW, etc.). The default frame is often RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW, which can produce unexpected results when you need a fixed-size sliding window or when handling ties in ORDER BY columns. Frame specification directly impacts both correctness and performance: a poorly specified frame forces the database to reconsider row membership for every input row, while an optimal frame can be computed incrementally.

The key distinction: ROWS treats frame boundaries as absolute row counts (e.g., "include the previous 2 rows"), while RANGE treats them as value-based (e.g., "include all rows where salary is within 5000 of current row"). RANGE with ties in the ORDER BY clause will include all tied values, which is semantically correct but can explode the frame size unexpectedly. Without explicit frame specification, many analysts accidentally compute running totals over the entire partition, or encounter performance cliffs when the optimizer can't parallelize frame computation efficiently.

## Practice

**Problem:** For each job posting, calculate the average salary among all jobs posted in the same location within the last 30 days (relative to that job's posting date). Show job_id, job_title_short, salary_year_avg, and the 30-day rolling average salary.

```sql
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  ROUND(
    AVG(salary_year_avg) OVER (
      PARTITION BY job_location
      ORDER BY job_posted_date
      RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW
    ),
    2
  ) AS avg_salary_30d_rolling
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
ORDER BY job_location, job_posted_date;
```

**Why this frame works:** RANGE with INTERVAL ensures date-based boundaries (not row counts), and BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW includes all jobs posted from exactly 30 days ago through today for each row. PARTITION BY job_location ensures no cross-location contamination. If you'd used the default frame, you'd get a cumulative average from the start of the partition instead.

## Notes

- **ROWS vs RANGE confusion:** ROWS BETWEEN 1 PRECEDING AND CURRENT ROW always means exactly 2 rows; RANGE BETWEEN INTERVAL '1 day' PRECEDING AND CURRENT ROW includes all rows within a 1-day span, so it can include 1, 10, or 100 rows depending on posting density.
- **Tie handling:** When ORDER BY has ties (e.g., multiple jobs posted on the same day), RANGE expands the frame to include all tied rows. This is usually correct but can silently inflate your frame size; use ROWS if you need deterministic, row-count-based boundaries.
- **Performance pitfall:** Frame specification affects whether the window function can be computed in a single streaming pass or requires multiple passes. Explicit, sensible frames (e.g., ROWS BETWEEN 1 PRECEDING AND CURRENT ROW) often enable better plan pushdown and parallelization than complex RANGE clauses.
- **Adjacent topics:** Frame specification interacts with ORDER BY nullability (NULLs sort first or last, affecting boundary inclusion), partitioning strategy (wide partitions = larger frames = slower computation), and aggregate function choice (SUM/AVG stream-friendly; FIRST_VALUE/LAST_VALUE benefit from ROWS).
- **Revisit:** Benchmark your frame spec against actual data; a query that looks correct can become a performance disaster once posting density varies across locations or date ranges change.
