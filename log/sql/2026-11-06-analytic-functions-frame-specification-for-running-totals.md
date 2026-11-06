---
date: 2026-11-06
phase: sql
topic: Analytic functions: frame specification for running totals
---

# Analytic functions: frame specification for running totals

*SQL for analytics and engineering*

## Concept

Frame specification in window functions defines the physical or logical range of rows the function operates over within a partition. For running totals, the frame must start at the partition boundary and extend to the current row—typically expressed as `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`. Without explicit frame specification, many databases apply a default frame that changes per function type (e.g., `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` for aggregate functions), which can silently produce wrong results when ties exist in the `ORDER BY` column or when you need true row-by-row accumulation rather than range-based grouping.

Running totals require precise control because the frame expands one row at a time. If you omit the frame clause and rely on defaults, a `SUM()` with ties in the order column may jump by multiple rows at once, breaking the cumulative sequence. Explicit `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` anchors the computation to physical row order, guaranteeing incrementalism even when salary or date values repeat.

## Practice

**Problem:** For each job location, calculate a running total of average salaries ordered by job posting date. Show job_id, location, job_posted_date, salary_year_avg, and the running cumulative average salary per location.

```sql
SELECT
  job_id,
  job_location,
  job_posted_date,
  salary_year_avg,
  AVG(salary_year_avg) 
    OVER (
      PARTITION BY job_location 
      ORDER BY job_posted_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_avg_salary
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
ORDER BY job_location, job_posted_date;
```

## Notes

- **Default frame gotcha**: `ORDER BY` without explicit frame causes `RANGE` semantics; all rows with identical order values enter/leave the frame together, skipping rows in a running total.
- **`ROWS` vs. `RANGE`**: `ROWS` counts physical rows; `RANGE` counts logical values. For true running totals, use `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`.
- **NULL handling**: NULLs sort first (or last, depending on DB) but don't break frame logic; filter or coalesce if needed to avoid NULL in aggregates.
- **Performance consideration**: Frame specification is explicit but not always slower; it lets the optimizer see intent and can enable incremental computation, unlike implicit defaults that require re-evaluation.
- **Related**: frame specifications apply to all window functions (LAG, LEAD, RANK, ROW_NUMBER), not just aggregates; PARTITION BY interacts with ORDER BY to define the boundary of the window.
