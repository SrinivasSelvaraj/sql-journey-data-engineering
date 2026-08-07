---
date: 2026-08-07
phase: sql
topic: Running totals and moving averages
---

# Running totals and moving averages

*SQL for analytics and engineering*

## Concept

Running totals and moving averages are window functions that aggregate data sequentially over a defined subset of rows, preserving the original row structure. A running total accumulates values from the start (or partition start) up to the current row; a moving average smooths noise by averaging a fixed window of surrounding rows. These are essential for time-series analysis, detecting trends, and comparing current performance against cumulative or recent historical context—tasks that would require self-joins or expensive subqueries without window functions.

Without window functions, you'd either denormalize data with multiple joins (quadratic complexity) or lose the original row context entirely by collapsing into GROUP BY aggregates. Running totals and moving averages let you keep row-level detail while adding computed context, making them unavoidable in analytics queries that track KPIs over time, measure month-to-date or rolling 7-day metrics, or flag anomalies against a baseline.

The performance difference is dramatic: a correlated subquery approach scales O(n²) or worse, while a single pass with `SUM(... OVER (...))` scales O(n log n) and fits in a single table scan or sort. Interview contexts value these because they test understanding of order semantics, frame boundaries, and execution efficiency.

## Practice

**Problem:** For each job posting, calculate the cumulative count of postings by that title up to that date, and the 30-day moving average salary for that title.

```sql
SELECT
  job_id,
  job_title_short,
  job_posted_date,
  salary_year_avg,
  COUNT(*) OVER (
    PARTITION BY job_title_short
    ORDER BY job_posted_date
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS cumulative_postings_by_title,
  AVG(salary_year_avg) OVER (
    PARTITION BY job_title_short
    ORDER BY job_posted_date
    ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
  ) AS salary_avg_30d
FROM job_postings_fact
ORDER BY job_title_short, job_posted_date;
```

## Notes

- **Frame boundaries matter:** `ROWS BETWEEN ... AND ...` is literal (counts rows); `RANGE BETWEEN ... AND ...` uses value distance and handles ties better. Forget the frame clause entirely and you get the default (RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), which often works but can surprise on ties.

- **ORDER BY is mandatory:** Window functions without ORDER BY partition but don't order; running totals will be wrong. Always specify ORDER BY inside the OVER clause; it does not change the outer result set ordering.

- **NULL handling:** SUM and AVG skip NULLs by default; COUNT(*) counts them. If salary_year_avg is NULL for some rows, the moving average excludes those rows from the denominator. Use COALESCE or filter upstream if that's not intended.

- **Performance: watch the frame size.** A 365-day moving average on 10M rows with many partitions can spill to disk. Start with ROWS (bounded) before RANGE (unbounded lookback), and consider pre-aggregating if the window is very wide.

- **Adjacent topics:** LAG/LEAD for period-over-period deltas, FIRST_VALUE/LAST_VALUE for benchmarking, PERCENT_RANK and NTILE for cohort analysis, and materialized windows (CTEs or tables) when the same window is computed many times in one query.
