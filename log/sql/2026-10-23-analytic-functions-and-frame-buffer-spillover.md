---
date: 2026-10-23
phase: sql
topic: Analytic functions and frame buffer spillover
---

# Analytic functions and frame buffer spillover

*SQL for analytics and engineering*

## Concept

Analytic (window) functions compute aggregate or ranking values across a defined subset of rows—the *window frame*—without collapsing rows like `GROUP BY` does. The frame is defined by `OVER (PARTITION BY ... ORDER BY ... ROWS/RANGE ...)`. When a frame grows large relative to available memory, the database must *spill* intermediate results to disk, causing dramatic performance degradation. This happens most often with unbounded frames (`ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`) or large ordered windows on high-cardinality data.

Frame buffer spillover becomes critical in production when you're computing running totals, cumulative distributions, or dense ranks over millions of rows. Without careful frame specification, a query that runs in seconds on 100K rows may timeout on 10M rows. The query plan will show sort operations and hash aggregate nodes marked with spill warnings; these are your signal that the window frame is too large for the sort buffer.

The fix is almost always to *narrow the frame intentionally*—use `ROWS BETWEEN ... AND ...` with concrete boundaries, or `RANGE BETWEEN INTERVAL '30 days' PRECEDING ...` instead of unbounded logic. Test frame size assumptions early by running `EXPLAIN ANALYZE` and checking sort memory allocation.

## Practice

**Problem:** For each job posting, calculate the 30-day moving average salary and the rank of that posting by salary within its location. Return only postings where the moving average exceeds $100k. Optimize for spillover risk on 2M+ rows.

```sql
SELECT
  job_id,
  job_title_short,
  job_location,
  salary_year_avg,
  ROUND(
    AVG(salary_year_avg) 
      OVER (
        PARTITION BY job_location
        ORDER BY job_posted_date
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
      ),
    0
  ) AS salary_ma_30d,
  RANK() 
    OVER (
      PARTITION BY job_location
      ORDER BY salary_year_avg DESC
    ) AS salary_rank_in_location
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
HAVING
  ROUND(
    AVG(salary_year_avg) 
      OVER (
        PARTITION BY job_location
        ORDER BY job_posted_date
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
      ),
    0
  ) > 100000
ORDER BY job_location, job_posted_date DESC;
```

**Key optimization moves:**  
• Used `ROWS BETWEEN 29 PRECEDING AND CURRENT ROW` (bounded) instead of unbounded frame for the moving average.  
• Rank frame is unbounded but only by salary (no ORDER BY date), so it sorts on a single column and usually fits in memory.  
• Both `PARTITION BY` clauses keep window size proportional to location cardinality, not global row count.

## Notes

- **Unbounded frames are the #1 spillover culprit.** Always ask: "Does my frame really need every row from the start of time?" Use `ROWS BETWEEN 100 PRECEDING AND CURRENT ROW` or date-based ranges instead.

- **Spill detection in plans:** Look for `Sort Method: external (disk)` or hash aggregate memory warnings in `EXPLAIN ANALYZE`. That's your cue to shrink or reorder the frame.

- **ORDER BY cardinality matters.** Partitioning by low-cardinality columns and ordering by high-cardinality (e.g., timestamp) usually spills less than the reverse, because sort groups are smaller.

- **RANGE vs. ROWS trade-off:** `RANGE BETWEEN ... PRECEDING` is more intuitive for business logic (e.g., "last 30 days") but may include more rows than `ROWS`. Test both; sometimes explicit row counts beat semantic clarity on large datasets.

- **Related deep dives:** query plan reading (sort/hash nodes), partition key selection for skew, and cumulative sum patterns—all interact with spillover risk. Revisit when optimizing real-time analytics pipelines.
