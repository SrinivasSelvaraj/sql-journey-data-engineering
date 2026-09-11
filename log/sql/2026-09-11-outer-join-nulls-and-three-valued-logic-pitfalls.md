---
date: 2026-09-11
phase: sql
topic: Outer join NULLs and three-valued logic pitfalls
---

# Outer join NULLs and three-valued logic pitfalls

*SQL for analytics and engineering*

## Concept

Outer joins introduce NULLs into result sets, and NULLs in SQL follow three-valued logic (TRUE, FALSE, NULL) rather than two-valued Boolean logic. This means `WHERE column = NULL` silently fails—it returns NULL, not a match—because NULL represents "unknown," not a value. When you outer join to find unmatched rows, filtering with `WHERE joined_table.key_column = NULL` or `WHERE joined_table.key_column IS NOT NULL` becomes critical; the same filter can flip your results entirely depending on placement (INNER vs. outer join semantics).

Without understanding three-valued logic, you'll write queries that silently drop rows you intended to keep. For example, `LEFT JOIN users ON orders.user_id = users.id WHERE users.id IS NOT NULL` is logically equivalent to an INNER JOIN—it eliminates the entire point of the outer join. Conversely, forgetting `IS NOT NULL` when you want to find unmatched rows (e.g., jobs never applied to) means your query returns nothing or wrong results. Analytics queries often need to count "missing" or "no match" scenarios; precision here directly impacts correctness of metrics.

## Practice

**Problem:** Find all job postings that have never received any applications. You have `job_postings_fact` and `applications_fact(application_id, job_id, application_date)`. Return job_id, job_title_short, and a flag `has_applications`. Ensure the query correctly identifies jobs with zero applications.

```sql
SELECT 
  jp.job_id,
  jp.job_title_short,
  CASE WHEN a.job_id IS NOT NULL THEN 1 ELSE 0 END AS has_applications
FROM job_postings_fact jp
LEFT JOIN applications_fact a ON jp.job_id = a.job_id
WHERE a.job_id IS NULL
ORDER BY jp.job_id;
```

**Why this works:** The `LEFT JOIN` preserves all jobs. The `WHERE a.job_id IS NULL` filter explicitly selects rows where the join found no match (NULL injected by outer join). If you wrote `WHERE a.job_id = a.job_id` or omitted the WHERE clause, you'd get wrong results. The CASE statement shows the logic; here it's always 0 because we filtered for NULL.

## Notes

- **Three-valued logic trap:** `NULL = NULL` returns NULL (unknown), not TRUE. Always use `IS NULL` or `IS NOT NULL`; equality operators fail silently.
- **WHERE vs. ON clause:** Filters in the `ON` clause execute *before* the outer join (affects what rows join); `WHERE` executes *after* (can nullify the outer join). Place predicates carefully—use `ON` to control join cardinality, `WHERE` to filter the final result.
- **Aggregation with outer joins:** `COUNT(*)` counts all rows including NULL-filled ones; `COUNT(joined_table.column)` counts only non-NULL values. These give different answers and both are often correct depending on intent.
- **Adjacent topics:** COALESCE/IFNULL for replacing NULLs, FULL OUTER JOIN (rarely used in analytics but useful for reconciliation), and handling NULLs in GROUP BY and DISTINCT.
- **Interview red flag:** If your LEFT JOIN query returns the same row count as an INNER JOIN, you likely have a `WHERE` condition that filtered out all the NULLs you added. Always verify cardinality assumptions.
