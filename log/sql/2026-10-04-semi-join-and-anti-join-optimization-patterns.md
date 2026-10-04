---
date: 2026-10-04
phase: sql
topic: Semi-join and anti-join optimization patterns
---

# Semi-join and anti-join optimization patterns

*SQL for analytics and engineering*

## Concept

A **semi-join** returns rows from the left table where at least one match exists in the right table—without duplicating rows or returning columns from the right table. An **anti-join** is its opposite: rows from the left table where *no* match exists in the right table. These patterns matter because naive implementations using `JOIN` + `DISTINCT` or `IN (SELECT...)` can cause cartesian explosions (when one row matches many on the right) or force full scans when the optimizer can't push predicates down effectively.

Semi-joins are typically written as `WHERE EXISTS (SELECT 1 FROM ... WHERE ...)` or `WHERE col IN (SELECT col FROM ...)` with proper indexing. Anti-joins use `WHERE NOT EXISTS` or `WHERE col NOT IN (...)` with careful NULL handling—`NOT IN` fails silently if the subquery contains NULLs, making `NOT EXISTS` the safer choice. Understanding when to use these instead of a `LEFT JOIN + WHERE IS NULL` anti-join pattern is critical for avoiding full table scans and unnecessary data movement in large-scale analytics queries.

## Practice

**Problem:** Find all job postings that have received at least one application, without returning duplicate postings or application details. Then separately, find job postings in tech roles that have *never* received any applications for a report on stale listings.

```sql
-- Semi-join: postings with at least one application
SELECT DISTINCT jp.job_id, jp.job_title_short, jp.job_posted_date
FROM job_postings_fact jp
WHERE EXISTS (
  SELECT 1 
  FROM applications_fact ap 
  WHERE ap.job_id = jp.job_id
);

-- Anti-join: tech job postings with no applications
SELECT jp.job_id, jp.job_title_short, jp.job_posted_date
FROM job_postings_fact jp
WHERE NOT EXISTS (
  SELECT 1 
  FROM applications_fact ap 
  WHERE ap.job_id = jp.job_id
)
AND jp.job_title_short ILIKE '%analyst%' OR jp.job_title_short ILIKE '%engineer%';
```

## Notes

- **NULL trap:** `WHERE job_id IN (SELECT job_id FROM ... WHERE col IS NULL)` will return no rows even if matches exist; use `WHERE EXISTS` or explicitly filter NULLs in the subquery.
- **Optimizer behavior:** Semi/anti-joins allow the optimizer to stop after finding the first match per left row (early exit), whereas `LEFT JOIN + DISTINCT` must materialize the full cartesian product first—check EXPLAIN ANALYZE to confirm the plan uses a semi/anti-join node rather than a hash or merge join.
- **Subquery correlation:** Both patterns require the subquery to reference the outer table (`WHERE ap.job_id = jp.job_id`); uncorrelated subqueries defeat the purpose and waste resources.
- **Alternative: `LEFT JOIN + IS NULL`** works for anti-joins but is less readable and can perform worse on wide tables since all columns are carried through the join; `NOT EXISTS` is preferred in modern SQL engines.
- **Indexes matter:** Semi/anti-join performance relies on indexing the join key in the inner table (e.g., `applications_fact(job_id)`); without it, every outer row triggers a full scan of the inner table.
