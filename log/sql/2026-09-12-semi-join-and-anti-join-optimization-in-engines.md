---
date: 2026-09-12
phase: sql
topic: Semi-join and anti-join optimization in engines
---

# Semi-join and anti-join optimization in engines

*SQL for analytics and engineering*

## Concept

A **semi-join** returns rows from the left table where at least one match exists in the right table, without duplicating left-side rows or returning right-side columns. An **anti-join** returns rows from the left table where *no* match exists in the right table. Both are optimization patterns that allow query engines to prune irrelevant data early.

The key difference from INNER JOIN: a semi-join stops searching once it finds one matching row, whereas INNER JOIN continues and produces a Cartesian product if multiple matches exist. Anti-join is the logical negation—typically expressed as NOT EXISTS or NOT IN (with NULL handling care). These patterns matter because careless use of JOIN + DISTINCT or multiple filtering conditions can force the engine to materialize large intermediate results. A well-written semi/anti-join pushes the filtering down into the join operation itself, reducing memory and I/O.

Without semi-join awareness, you end up writing inefficient queries: using IN with subqueries that return duplicates, or LEFT JOIN + WHERE IS NULL that still scans and joins the entire right table before filtering. Engines with good cost-based optimization will rewrite these patterns internally, but explicit semi-join syntax or correct NOT EXISTS usage ensures predictability and often outperforms implicit optimization, especially in large-scale analytics.

## Practice

**Problem:** Find all job postings from the last 30 days that have *not* been filled (no matching record in a `job_applications_fact` table). Return job_id, job_title_short, and salary_year_avg, without duplicates, and with minimal overhead.

```sql
-- Anti-join approach: correct and efficient
SELECT 
    jp.job_id,
    jp.job_title_short,
    jp.salary_year_avg
FROM job_postings_fact jp
WHERE jp.job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY
  AND NOT EXISTS (
      SELECT 1
      FROM job_applications_fact ja
      WHERE ja.job_id = jp.job_id
  );
```

## Notes

- **NOT IN pitfall:** `WHERE job_id NOT IN (SELECT job_id FROM applications)` fails silently if the subquery contains NULLs (returns no rows). Use NOT EXISTS or LEFT JOIN + IS NULL instead.
- **Duplicate handling:** INNER JOIN followed by DISTINCT is slower than semi-join because it materializes the full Cartesian product first. Push filtering into the join condition or use semi-join syntax if your engine supports it (Presto, BigQuery, Spark SQL).
- **LEFT JOIN anti-pattern:** `LEFT JOIN applications ON jp.job_id = ja.job_id WHERE ja.job_id IS NULL` still scans the entire applications table. NOT EXISTS is semantically equivalent but allows early termination.
- **Engine-specific syntax:** Some engines (Presto, DuckDB) support explicit LEFT SEMI JOIN and LEFT ANTI JOIN; others (PostgreSQL, MySQL) require NOT EXISTS idiom. Always check your target engine's query plan to confirm the optimization was applied.
- **Connected topics:** Correlate this with understanding subquery execution models (scalar vs. correlated), join order optimization, and statistics-driven cardinality estimates. Also review when IN with small lists or hash-joins outperform NOT EXISTS in your specific engine.
