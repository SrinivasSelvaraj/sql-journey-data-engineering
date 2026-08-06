---
date: 2026-08-06
phase: sql
topic: Deduplication with window functions
---

# Deduplication with window functions

*SQL for analytics and engineering*

## Concept

Deduplication with window functions removes duplicate rows while retaining other columns, using `ROW_NUMBER()`, `RANK()`, or `DENSE_RANK()` to assign a position within a partition. Unlike `GROUP BY`, which collapses rows and forces aggregation, window functions preserve the full row context while marking duplicates for filtering. This is critical when you have multi-column keys, need to keep non-aggregated detail columns, or must select "the latest" or "the best" duplicate based on a business rule (e.g., highest salary, most recent posting date).

Without deduplication logic, joins or unions can multiply rows unexpectedly. For instance, joining a job postings table to a company table on a non-unique key will create a Cartesian product. Window functions solve this elegantly by ranking candidates per group—then filtering to `WHERE rn = 1`—without losing dimensional context that `GROUP BY` would sacrifice. Performance matters: window functions are O(n log n) to O(n) depending on the database optimizer; they're faster and clearer than self-joins or nested subqueries for most dedup scenarios.

## Practice

**Problem:** You have job postings that may be reposted under the same `job_id` on different dates. Keep only the most recent posting for each `job_id`, retaining all columns.

```sql
WITH ranked_postings AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY job_posted_date DESC) AS rn
  FROM job_postings_fact
)
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM ranked_postings
WHERE rn = 1;
```

## Notes

- **`ROW_NUMBER()` vs. `RANK()` vs. `DENSE_RANK()`:** Use `ROW_NUMBER()` for arbitrary tie-breaking (1, 2, 3, 4). Use `RANK()` when ties matter and you want gaps (1, 2, 2, 4). Use `DENSE_RANK()` for compact ranking without gaps (1, 2, 2, 3). For dedup, `ROW_NUMBER()` is usually correct.
- **ORDER BY direction:** `DESC` to grab the latest/highest; `ASC` to grab the earliest/lowest. The window function must have an unambiguous tie-breaker or use a secondary sort key (e.g., `job_posted_date DESC, job_id ASC`).
- **CTE clarity:** Wrapping the window function in a CTE makes the query readable and testable; filtering `WHERE rn = 1` outside avoids needing a subquery.
- **Adjacent topic:** Connects to `PARTITION BY` logic (grouping behavior), join cardinality (why dedup matters), and understanding query execution plans (window functions can trigger sorts/scans).
- **Interview trap:** Forgetting that `WHERE` filters *before* window functions execute; always filter dedup results *after* the window assignment, using a CTE or subquery.
