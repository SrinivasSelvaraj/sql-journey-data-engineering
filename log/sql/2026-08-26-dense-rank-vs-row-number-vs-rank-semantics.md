---
date: 2026-08-26
phase: sql
topic: Dense rank vs row number vs rank semantics
---

# Dense rank vs row number vs rank semantics

*SQL for analytics and engineering*

## Concept

`ROW_NUMBER()`, `RANK()`, and `DENSE_RANK()` are window functions that assign a position to each row within a partition, but they handle ties differently. `ROW_NUMBER()` assigns unique integers (1, 2, 3, 4) regardless of tied values—useful when you need a deterministic ordering for pagination or deduplication. `RANK()` assigns the same number to tied rows and skips the next numbers (1, 2, 2, 4), creating gaps; use this when you want to preserve the notion of "how many rows beat this one." `DENSE_RANK()` also assigns the same number to ties but does *not* skip numbers (1, 2, 2, 3), keeping a compact ranking; use this for analytics dashboards where you want "top 3" to mean exactly 3 distinct groups.

The difference matters most when you have tied values in your `ORDER BY` clause and you're filtering by rank (e.g., `WHERE dense_rank <= 10`). Using `RANK()` instead of `DENSE_RANK()` can give you 15 rows when you expected 10, because gaps inflate the result set. Conversely, `ROW_NUMBER()` can arbitrarily exclude tied rows, making it unsuitable for "top N distinct groups" queries. Without choosing correctly, you'll either miss data, over-fetch, or produce non-deterministic results depending on tie-breaking logic.

## Practice

**Problem:** Rank job postings by salary within each job title (short), keeping only the top 3 highest-paying postings per title. You must return exactly 3 rows per title group, even if salaries are tied at the boundary.

```sql
SELECT
  job_title_short,
  job_id,
  salary_year_avg,
  job_location,
  dense_rank() OVER (PARTITION BY job_title_short ORDER BY salary_year_avg DESC) as salary_rank
FROM job_postings_fact
WHERE dense_rank() OVER (PARTITION BY job_title_short ORDER BY salary_year_avg DESC) <= 3
QUALIFY dense_rank() OVER (PARTITION BY job_title_short ORDER BY salary_year_avg DESC) <= 3
ORDER BY job_title_short, salary_rank;
```

**Note:** Use `QUALIFY` (or a CTE) to filter on the window function result; you cannot use `WHERE` directly on window functions. `DENSE_RANK()` ensures that if three jobs tie at $120k salary, they all get rank 3, and rank 4 is skipped—but you still get exactly 3 rows per title group, not gaps.

## Notes

- **Common mistake:** Using `RANK()` expecting top-N results and getting more rows than expected because of gaps; always use `DENSE_RANK()` for "top K distinct groups."
- **ROW_NUMBER() gotcha:** It requires a deterministic tiebreaker (e.g., `ORDER BY salary DESC, job_id ASC`) or results vary across query runs; avoid it for ranking unless you explicitly want arbitrary tie-breaking.
- **QUALIFY vs. CTE:** `QUALIFY` is cleaner for single-window filtering but less portable (Snowflake, Databricks, DuckDB); CTEs work everywhere and are clearer for complex logic.
- **Adjacent concept—NTILE():** Divides rows into equal buckets (quartiles, deciles); complements these rank functions for percentile-based analysis.
- **Revisit:** Test edge cases with 100% tied values; ensure your `PARTITION BY` and `ORDER BY` clauses match the business question (e.g., ranking by salary, not by posting date).
