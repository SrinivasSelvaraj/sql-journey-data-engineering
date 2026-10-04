---
date: 2026-10-04
phase: sql
topic: Set operations: intersection and except complexity
---

# Set operations: intersection and except complexity

*SQL for analytics and engineering*

## Concept

Set operations in SQL (`UNION`, `INTERSECT`, `EXCEPT`) allow you to combine or compare result sets, but their performance characteristics differ significantly from joins. `INTERSECT` returns rows present in both queries; `EXCEPT` returns rows in the first query but not the second. Both require the database to materialize full result sets, sort them, and deduplicate—operations that scale poorly with large datasets and become O(n log n) rather than the O(n) of a well-indexed join.

The critical performance difference: set operations ignore column relationships and compare *entire rows*, meaning they demand identical column counts and compatible types across both queries. This makes them useful for finding exact duplicates or logical set membership, but inefficient for filtering. A query like `SELECT * FROM table_a EXCEPT SELECT * FROM table_b` will full-scan both tables, sort both results, and then compute the difference—even if a simple `LEFT JOIN WHERE IS NULL` would use indexes and run an order of magnitude faster.

Set operations matter most when you genuinely need set semantics (e.g., finding candidates who applied but were never hired, or skills appearing in exactly two job postings). When you're tempted to use `INTERSECT` or `EXCEPT`, ask: "Can I express this as a join with a filter condition?" Usually, the answer improves both readability and performance.

## Practice

**Problem:** Find job titles that were posted in 2023 but have *never* appeared in any 2024 posting. Return the distinct titles.

```sql
SELECT DISTINCT job_title_short
FROM job_postings_fact
WHERE YEAR(job_posted_date) = 2023

EXCEPT

SELECT DISTINCT job_title_short
FROM job_postings_fact
WHERE YEAR(job_posted_date) = 2024;
```

**Why this works:** `EXCEPT` compares the two sets of titles row-by-row and returns only titles in the first set absent from the second. The `DISTINCT` ensures we're comparing unique titles, not bloating the result set with duplicates.

**Better alternative (often faster):**
```sql
SELECT DISTINCT j2023.job_title_short
FROM job_postings_fact j2023
WHERE YEAR(j2023.job_posted_date) = 2023
  AND NOT EXISTS (
    SELECT 1
    FROM job_postings_fact j2024
    WHERE YEAR(j2024.job_posted_date) = 2024
      AND j2024.job_title_short = j2023.job_title_short
  );
```

## Notes

- **Set operations deduplicate implicitly** (except `UNION ALL`); if you need duplicates preserved, use `ALL` or rewrite as a join to avoid unnecessary overhead.
- **Column order and type coercion matter:** `INTERSECT` and `EXCEPT` match by position, not name. Misaligned columns silently produce wrong results; use explicit `SELECT` lists, never `SELECT *`.
- **NULL handling differs:** `NULL = NULL` is false in SQL, but set operations treat two `NULL` values as identical rows. This asymmetry can surprise you when comparing nullable columns.
- **Revisit NOT EXISTS vs. EXCEPT:** For filtering one table against another, `NOT EXISTS` is usually faster because it can short-circuit and leverage indexes; `EXCEPT` always materializes both full sets.
- **Use `EXCEPT` for true set logic** (e.g., "which users never purchased?"), **join + filter for analytics** (e.g., "show me user details where they never purchased"). Know which tool solves your problem cleanly.
