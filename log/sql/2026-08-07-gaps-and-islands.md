---
date: 2026-08-07
phase: sql
topic: Gaps and islands
---

# Gaps and islands

*SQL for analytics and engineering*

## Concept

Gaps and islands is a SQL pattern for identifying contiguous groups of rows based on some ordering or sequence. An "island" is a consecutive sequence of records that share a property; a "gap" is a break in that sequence. This arises frequently in time-series analysis, event logs, and state transitions—for example, identifying periods when a user was continuously active, or grouping consecutive days of work without breaks.

The classic technique uses a window function to assign each row a group identifier by calculating the difference between a row number and a date (or sequence). If that difference is constant within a logical group, rows belong to the same island. Without this pattern, you either miss the grouping entirely or resort to expensive self-joins and row-by-row comparisons that tank query performance.

Real-world impact: detecting consecutive login sessions, finding streaks of job postings from the same company, or measuring uninterrupted uptime windows. Mishandling this forces O(n²) logic and nested loops; the window function approach is O(n log n) and scales.

## Practice

**Problem:** For each job location, find all contiguous date ranges where job postings occurred every single day (no gaps). Group these islands and count how many postings fall within each island.

```sql
WITH daily_postings AS (
  SELECT 
    job_location,
    job_posted_date,
    ROW_NUMBER() OVER (PARTITION BY job_location ORDER BY job_posted_date) AS rn
  FROM job_postings_fact
  GROUP BY job_location, job_posted_date
),
islands AS (
  SELECT 
    job_location,
    job_posted_date,
    DATE_SUB(job_posted_date, INTERVAL rn DAY) AS island_id
  FROM daily_postings
),
island_summary AS (
  SELECT 
    job_location,
    island_id,
    MIN(job_posted_date) AS island_start,
    MAX(job_posted_date) AS island_end,
    COUNT(*) AS consecutive_days
  FROM islands
  GROUP BY job_location, island_id
)
SELECT 
  job_location,
  island_start,
  island_end,
  consecutive_days,
  (SELECT COUNT(*) FROM job_postings_fact 
   WHERE job_location = island_summary.job_location 
   AND job_posted_date BETWEEN island_start AND island_end) AS total_postings_in_island
FROM island_summary
ORDER BY job_location, island_start;
```

## Notes

- **Window function order matters:** `ROW_NUMBER()` must partition by the grouping key and order by the sequence column; reversing order produces wrong islands.
- **The magic trick:** subtracting row_number from date/timestamp creates a constant for each contiguous group; this only works because both increase uniformly.
- **Edge case—multi-day gaps:** if you need islands with *up to N days* of allowed gaps, add `INTERVAL N DAY` to the subtraction logic instead of `INTERVAL 1 DAY`.
- **Connects to:** cumulative sums (another window function pattern), time-bucketing, and retention cohorts in analytics.
- **Performance check:** verify the `GROUP BY` on raw postings completes first; if data is large, consider materializing `daily_postings` as a temp table to avoid rescanning.
