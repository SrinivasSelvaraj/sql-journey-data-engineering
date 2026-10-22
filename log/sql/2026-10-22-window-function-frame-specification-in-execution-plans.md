---
date: 2026-10-22
phase: sql
topic: Window function frame specification in execution plans
---

# Window function frame specification in execution plans

*SQL for analytics and engineering*

## Concept

Window function frame specification defines which rows participate in the computation for each row in a window. Without explicit frame definition, most databases default to `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`, which often produces unexpected results—especially for aggregates like `SUM()` or `AVG()`. The frame specification (`ROWS` vs. `RANGE`, boundaries like `PRECEDING`/`FOLLOWING`) directly impacts:
- **Query correctness**: A running sum may mysteriously stop accumulating or reset unexpectedly.
- **Performance**: Over-specified frames (e.g., `UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`) force the database to materialize large sets; tight frames enable streaming computation and partition pruning.

Frame specification is critical when analyzing time-series or ranked data. For example, calculating a 7-day moving average requires precise control: `ROWS BETWEEN 6 PRECEDING AND CURRENT ROW` is semantically different from `RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW`. The former counts exactly 7 rows; the latter includes all rows within a date range, handling gaps and duplicates differently. Without understanding this distinction, your execution plan may show unnecessary sorts, hash aggregates, or frame buffer operations that balloon memory usage.

## Practice

**Problem:** For each job posting, calculate the count of postings and the average salary in a 30-day window *after* that posting date (forward-looking window). Order results by job_posted_date and job_id.

```sql
SELECT 
    job_id,
    job_title_short,
    job_posted_date,
    salary_year_avg,
    COUNT(*) OVER (
        ORDER BY job_posted_date 
        RANGE BETWEEN CURRENT ROW AND INTERVAL '30 days' FOLLOWING
    ) AS postings_in_30d_window,
    ROUND(AVG(salary_year_avg) OVER (
        ORDER BY job_posted_date 
        RANGE BETWEEN CURRENT ROW AND INTERVAL '30 days' FOLLOWING
    ), 2) AS avg_salary_30d_forward
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
ORDER BY job_posted_date, job_id;
```

**Why this works:** `RANGE BETWEEN CURRENT ROW AND INTERVAL '30 days' FOLLOWING` respects the date semantics—it captures all postings within 30 calendar days ahead, regardless of row count. `ROWS BETWEEN` would be incorrect here because it counts physical rows, not temporal distance. The execution plan should show a window aggregate with a frame buffer (not a full sort to UNBOUNDED FOLLOWING), keeping memory footprint reasonable.

## Notes

- **Default frame gotcha:** Many engineers omit frame specification and inherit the database default, which is often `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` for aggregates—fine for cumulative metrics but wrong for centered or trailing windows.
- **ROWS vs. RANGE:** `ROWS` is positional (exactly N rows); `RANGE` is value-based (all rows within a value distance). Use `RANGE` for date/time windows; use `ROWS` for strict positional logic (e.g., "previous 3 rows").
- **Execution plan clues:** Look for "Frame Buffer" or "Materialize" operations in the plan. A forward-looking or centered frame often forces a full partition sort before windowing; optimize by partitioning/indexing on the order key.
- **NULL handling:** Window frames exclude NULLs in aggregate calculations by default (same as `AGGREGATE(... IGNORE NULLS)`). If you need different behavior, consider `COALESCE()` or explicit NULL ordering.
- **Adjacent topics:** Partition pruning (how `PARTITION BY` interacts with indexes), ranking functions (`ROW_NUMBER()` vs. `RANK()` have implicit `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`), and recursive CTEs for gap-filling in time-series data.
