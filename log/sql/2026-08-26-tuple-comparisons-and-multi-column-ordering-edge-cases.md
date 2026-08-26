---
date: 2026-08-26
phase: sql
topic: Tuple comparisons and multi-column ordering edge cases
---

# Tuple comparisons and multi-column ordering edge cases

*SQL for analytics and engineering*

## Concept

Tuple comparisons (also called row comparisons) allow you to compare multiple columns as a single unit using syntax like `(col1, col2) > (val1, val2)`. This is lexicographic ordering: SQL compares the first column; only if it's equal does it move to the second, and so on. This matters when you need to order or filter by multiple columns simultaneously—especially in pagination (keyset cursors), tie-breaking, or finding rows that dominate across several dimensions.

Without understanding tuple semantics, you risk incorrect results. For example, `WHERE (salary, job_id) > (100000, 5)` will skip rows with salary=100001 and job_id=1, because the tuple comparison fails when the second element is smaller even though the first is larger. Similarly, `ORDER BY col1, col2` and `WHERE (col1, col2) > (a, b)` must use identical column order; mismatches cause silent logic errors or poor plan choice (nested loop instead of index skip).

The performance edge case: databases optimize `(col1, col2) > (val1, val2)` into `col1 > val1 OR (col1 = val1 AND col2 > val2)` internally, but only when the optimizer recognizes the pattern. Non-standard syntax or unnecessary parentheses can prevent this expansion, forcing table scans instead of range seeks on a composite index.

## Practice

**Problem:** Paginate through job postings, sorted by salary (descending) then job_id (ascending). Given the last page's lowest salary (95000) and its job_id (42), fetch the next 10 rows without duplicates or gaps.

```sql
SELECT 
  job_id, 
  job_title_short, 
  salary_year_avg, 
  job_posted_date
FROM job_postings_fact
WHERE (salary_year_avg, job_id) < (95000, 42)
  AND salary_year_avg IS NOT NULL
ORDER BY salary_year_avg DESC, job_id ASC
LIMIT 10;
```

**Why this works:** The tuple comparison `(salary_year_avg, job_id) < (95000, 42)` enforces lexicographic ordering matching the ORDER BY. It expands to `salary_year_avg < 95000 OR (salary_year_avg = 95000 AND job_id > 42)`, skipping the previous page exactly. Without the `job_id` tie-breaker in both WHERE and ORDER BY, salary ties would shuffle unpredictably across pages.

## Notes

- **Order mismatch trap:** `ORDER BY salary DESC, job_id ASC` paired with `WHERE (salary, job_id) > (val1, val2)` uses *ascending* tuple order by default; you must flip the operator or explicitly use `DESC` in the WHERE to stay consistent. `(salary DESC, job_id ASC)` syntax is not standard SQL; rely on operator flipping instead.

- **Index utilization:** A composite index on `(salary_year_avg DESC, job_id ASC)` can execute the keyset-pagination query in a single ordered scan. Misaligned WHERE clauses or non-tuple filters like `salary > 95000 AND job_id > 42` (without the OR) lose the index and force a full table scan.

- **NULL handling:** Tuple comparisons treat `NULL` as a valid value in comparisons; `(NULL, 5) < (100, 1)` is `NULL` (unknown), not false. Always filter NULLs explicitly in the WHERE clause if they shouldn't appear.

- **Adjacency to window functions:** Keyset pagination is the performant alternative to `ROW_NUMBER() OVER (ORDER BY ...)` for large datasets. Window functions force materialization; tuple comparisons scale to billions of rows.

- **Revisit:** Test on your database's optimizer (EXPLAIN PLAN) to confirm the tuple comparison is being expanded correctly; some databases require hints or reformulation if the pattern isn't recognized.
