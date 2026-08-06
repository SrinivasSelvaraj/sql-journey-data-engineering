---
date: 2026-08-06
phase: sql
topic: Window frames: ROWS vs RANGE
---

# Window frames: ROWS vs RANGE

*SQL for analytics and engineering*

## Concept

Window frames define which rows participate in a window function calculation *within each partition*. **ROWS** counts physical rows (e.g., the literal 2 rows before the current row), while **RANGE** counts logical value ranges (e.g., all rows within 7 days of the current row's date). RANGE is order-sensitive and requires an ORDER BY clause; it groups rows with identical sort keys together.

The distinction matters when your data has ties or when you want value-based instead of position-based windows. Without explicit frame specification, most databases default to `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`, which can produce surprising cumulative sums or running averages. For example, if three job postings share the same date and you use `RANGE`, all three may see identical cumulative salary totals up to that date—not what you intended if you wanted per-row progression.

ROWS is deterministic and predictable for row-number-based logic (lag/lead patterns, top-N per group). RANGE is natural for time-based or value-based aggregations where ties should be treated as a cohort. Choosing wrong leads to off-by-one errors, incorrect running totals, or performance cliffs when RANGE forces full-partition scans instead of sliding windows.

## Practice

**Problem:** For each job posting, calculate a 7-day rolling average salary using the job posting date, ensuring that all postings on the same date see the same rolling average (value-based grouping, not row-based).

```sql
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_posted_date,
  AVG(salary_year_avg) OVER (
    ORDER BY job_posted_date
    RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW
  ) AS salary_7day_rolling_avg
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
ORDER BY job_posted_date, job_id;
```

**Contrast (ROWS, incorrect for this use case):** Using `ROWS BETWEEN 6 PRECEDING AND CURRENT ROW` would average exactly 7 physical rows regardless of date gaps, misaligning the window semantics. If you posted 5 jobs on Monday and 2 on Tuesday, ROWS would mix them unpredictably; RANGE keeps the 7-day boundary clean.

## Notes

- **Default frame gotcha:** `ORDER BY` without an explicit frame defaults to `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`, making cumulative aggregates non-obvious. Always state your frame explicitly for clarity.
- **ROWS requires integer offsets** (ROWS BETWEEN 3 PRECEDING AND 1 FOLLOWING); **RANGE requires an ORDER BY expression and matching interval type** (INTERVAL or numeric, depending on column). Mismatch = syntax error.
- **Ties and consistency:** RANGE treats all rows with the same ORDER BY value as simultaneous; useful for "all postings on 2025-01-15 share the same aggregate." ROWS never groups ties unless you explicitly set the frame width.
- **Performance:** ROWS can use sliding-window algorithms (fast); RANGE may force full-partition evaluation, especially with non-equidistant intervals. Test on large datasets.
- **Related:** LAG/LEAD use implicit ROWS framing (single row); SUM/AVG/COUNT require explicit frames. Revisit PARTITION BY independence—frames are *per partition*, not global.
