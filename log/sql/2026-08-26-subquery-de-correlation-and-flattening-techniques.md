---
date: 2026-08-26
phase: sql
topic: Subquery de-correlation and flattening techniques
---

# Subquery de-correlation and flattening techniques

*SQL for analytics and engineering*

## Concept

A correlated subquery executes once for every row in the outer query, making it O(n²) or worse—expensive when n is large. Subquery de-correlation rewrites it as a JOIN or window function, executing once and achieving O(n log n) performance. This is critical in analytics: a correlated subquery on 100k rows can take seconds; the flattened equivalent takes milliseconds.

Flattening techniques include converting `WHERE EXISTS` or `WHERE IN` into `INNER JOIN`, replacing scalar subqueries with `LEFT JOIN` + aggregation, and using window functions (`ROW_NUMBER()`, `SUM() OVER()`) instead of grouped subqueries. The optimizer sometimes does this automatically, but understanding when to flatten manually ensures you write correct, efficient SQL under time pressure—and helps you reason about query plans when EXPLAIN shows a nested loop join instead of a hash join.

Without de-correlation, you risk query timeouts, lock contention, and platform-enforced query limits. Learning to spot correlated subqueries and flatten them is a high-ROI skill: it separates performant analytics SQL from code that "works" but grinds the database.

## Practice

**Problem:** Find the job title and salary for all jobs posted after the average posting date, where the salary is above the median salary within that job title category.

```sql
-- ❌ Inefficient (correlated subqueries)
SELECT jp.job_id, jp.job_title_short, jp.salary_year_avg
FROM job_postings_fact jp
WHERE jp.job_posted_date > (SELECT AVG(job_posted_date) FROM job_postings_fact)
  AND jp.salary_year_avg > (
    SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg)
    FROM job_postings_fact
    WHERE job_title_short = jp.job_title_short
  );

-- ✅ De-correlated (window function + subquery elimination)
WITH avg_date AS (
  SELECT AVG(job_posted_date) AS avg_posted_date FROM job_postings_fact
),
salary_medians AS (
  SELECT job_title_short,
         PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) AS median_salary
  FROM job_postings_fact
  GROUP BY job_title_short
)
SELECT jp.job_id, jp.job_title_short, jp.salary_year_avg
FROM job_postings_fact jp
INNER JOIN avg_date ad ON jp.job_posted_date > ad.avg_posted_date
INNER JOIN salary_medians sm ON jp.job_title_short = sm.job_title_short
  AND jp.salary_year_avg > sm.median_salary;
```

## Notes

- **Spot correlated subqueries:** Look for references to outer table aliases inside `WHERE (SELECT ... FROM ... WHERE outer.col = ...)`. That's your signal to flatten.
- **De-correlation patterns:** `EXISTS` → `INNER JOIN` (deduped if needed); scalar subquery in `SELECT` → `LEFT JOIN` + window function; `IN (SELECT ...)` → `INNER JOIN` (watch for NULL handling).
- **Window functions are de-correlated by nature:** `ROW_NUMBER() OVER (PARTITION BY ...)` replaces subquery rank logic in O(n log n) instead of O(n²).
- **Test with EXPLAIN:** Always run `EXPLAIN` or `EXPLAIN ANALYZE` on both versions. Look for "Nested Loop" (bad sign) vs. "Hash Join" or "Merge Join" (good sign).
- **Adjacent topics:** Query plan analysis, NULL semantics in `LEFT JOIN` (NULLs don't match in `IN (SELECT)`), materialized CTEs (temp tables) for readability when de-correlation gets complex.
