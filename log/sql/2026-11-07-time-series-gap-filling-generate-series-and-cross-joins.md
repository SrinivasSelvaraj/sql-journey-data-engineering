---
date: 2026-11-07
phase: sql
topic: Time series gap filling: generate_series and cross joins
---

# Time series gap filling: generate_series and cross joins

*SQL for analytics and engineering*

## Concept

Time series gap filling is the process of creating a complete sequence of time periods (days, months, years) and joining actual data to it, ensuring every period appears in results even when no events occurred. Without gap filling, your analysis shows only periods with activity, making trends invisible and calculations misleading. This is critical for metrics like daily active users, cumulative revenue, or sequential event tracking—gaps in the data become gaps in the story.

The core technique uses `generate_series()` to create the complete date range, then a `LEFT JOIN` or `CROSS JOIN` to attach actual data. `generate_series(start_date, end_date, interval)` produces rows for every unit in the range; `CROSS JOIN` multiplies two tables to create all combinations (useful for pairing multiple dimensions like job locations with all dates). The cross join approach scales well for dimensions—e.g., every job category × every month—without exploding the date table itself.

Without gap filling, you'll undercount periods, miscalculate growth rates, and miss seasonality. Interview contexts often include a vague requirement like "show posting trends over time" that silently expects complete dates; submitting a query with gaps looks like incomplete thinking about the problem domain.

## Practice

**Problem:** List every day from 2023-01-01 to 2023-12-31, with the count of job postings posted on that day. Include days with zero postings.

```sql
WITH date_series AS (
  SELECT generate_series('2023-01-01'::DATE, '2023-12-31'::DATE, '1 day'::INTERVAL)::DATE AS posting_date
),
daily_postings AS (
  SELECT job_posted_date::DATE AS posting_date, COUNT(*) AS post_count
  FROM job_postings_fact
  WHERE job_posted_date::DATE BETWEEN '2023-01-01' AND '2023-12-31'
  GROUP BY job_posted_date::DATE
)
SELECT ds.posting_date, COALESCE(dp.post_count, 0) AS post_count
FROM date_series ds
LEFT JOIN daily_postings dp ON ds.posting_date = dp.posting_date
ORDER BY ds.posting_date;
```

## Notes

- **Type casting matters:** `generate_series()` with INTERVAL returns TIMESTAMP; cast to DATE for joins. Mismatched types cause silent non-joins.
- **CROSS JOIN for dimensions:** If you need every job_title_short × every date, use `date_series CROSS JOIN (SELECT DISTINCT job_title_short FROM job_postings_fact)` before LEFT JOIN to actual data—this prevents dimension elimination.
- **Performance consideration:** `generate_series()` is set-returning and evaluated early; for massive ranges (10 years daily), consider materializing into a temp table or CTE to avoid repeated evaluation.
- **COALESCE for nulls:** LEFT JOIN produces NULLs on the right side when no match exists; wrap aggregates like `COUNT()` in `COALESCE(dp.post_count, 0)` to show zero instead of NULL.
- **Adjacent topic:** Cumulative sums (running totals) often follow gap filling—use `SUM() OVER (ORDER BY date)` after gap-filling to avoid jumps in cumulative values.
