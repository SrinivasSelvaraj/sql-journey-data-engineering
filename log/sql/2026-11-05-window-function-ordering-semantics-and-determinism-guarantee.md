---
date: 2026-11-05
phase: sql
topic: Window function ordering semantics and determinism guarantees
---

# Window function ordering semantics and determinism guarantees

*SQL for analytics and engineering*

## Concept

Window functions in SQL partition data and apply aggregations or rankings *within* each partition. The `ORDER BY` clause inside the `OVER()` clause determines two critical things: (1) the *frame* over which the window operates (which rows are included in a running sum, average, or rank), and (2) the *deterministic ordering* for rank-based functions like `ROW_NUMBER()`, `RANK()`, and `DENSE_RANK()`.

Without explicit `ORDER BY` in your window definition, you lose determinism. Two identical queries can return different row numbers or ranks across runs if the database chooses different execution plans, because rows with the same partition key have no guaranteed order. This is especially dangerous in interview settings or production: a query that passes testing on sample data may behave unpredictably at scale or after schema changes. For analytical queries, you must always specify `ORDER BY` unless you explicitly want an unordered frame (rare).

The frame itself—`ROWS BETWEEN...` or `RANGE BETWEEN...`—is implicitly set when you add `ORDER BY`. By default, it becomes `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` for running calculations, not the full partition. This surprises many people: a running sum with `ORDER BY date` will not sum the entire partition unless you explicitly write `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`.

## Practice

**Problem:** Rank job postings within each job title by salary (highest first), and calculate a running count of postings as salary decreases. Identify which posting is the highest-paid for each title. Return only postings where the rank is 1 or 2.

```sql
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  RANK() OVER (
    PARTITION BY job_title_short
    ORDER BY salary_year_avg DESC
  ) AS salary_rank,
  COUNT(*) OVER (
    PARTITION BY job_title_short
    ORDER BY salary_year_avg DESC
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS running_count_of_postings
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
QUALIFY RANK() OVER (PARTITION BY job_title_short ORDER BY salary_year_avg DESC) <= 2
ORDER BY job_title_short, salary_rank;
```

The `QUALIFY` clause filters after window functions evaluate (equivalent to `WHERE` on window results). The explicit `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` makes the running count deterministic and correct.

## Notes

- **Determinism without ORDER BY is undefined behavior.** Even if your test data is small, production data may expose non-deterministic row ordering. Always include `ORDER BY` or document why the partition is intentionally unordered (almost never justified).

- **RANGE vs. ROWS frame semantics differ subtly.** `RANGE` groups rows with identical `ORDER BY` values together; `ROWS` treats each physical row separately. For `ROW_NUMBER()` this doesn't matter; for `SUM()` with tied values, it does. Prefer explicit frame syntax to avoid surprises.

- **NULL handling in ORDER BY.** NULLs sort first (ascending) or last (descending) by default; behavior varies by database. If salary can be NULL, explicitly handle it: `ORDER BY salary_year_avg DESC NULLS LAST` or filter `WHERE salary_year_avg IS NOT NULL` upstream.

- **Window functions evaluate *before* `WHERE` but *after* `FROM` and `JOIN`.** This means you cannot filter on a window function result in `WHERE`; use `QUALIFY` (Snowflake, BigQuery, Postgres 13+) or a subquery/CTE instead.

- **Connects to:** query optimization (window functions can be expensive at scale; consider materialization), frame specification tuning (UNBOUNDED vs. bounded frames affect execution), and tie-breaking logic (always add secondary `ORDER BY` columns to ensure determinism when primary column has duplicates).
