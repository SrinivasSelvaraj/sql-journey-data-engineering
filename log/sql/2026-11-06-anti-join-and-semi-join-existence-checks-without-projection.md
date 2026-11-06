---
date: 2026-11-06
phase: sql
topic: Anti-join and semi-join: existence checks without projection
---

# Anti-join and semi-join: existence checks without projection

*SQL for analytics and engineering*

## Concept

An **anti-join** returns rows from the left table where *no* matching row exists in the right table. A **semi-join** returns rows from the left table where *at least one* matching row exists in the right table—but crucially, it returns only the left table's columns, never columns from the right. Both exist to answer "does this thing exist?" without materializing unnecessary data or creating row multiplication.

The core efficiency win: semi-joins and anti-joins avoid duplicating left rows when the right table has multiple matches. A conventional `INNER JOIN` followed by `DISTINCT` or `GROUP BY` will scan and process all matching pairs; a semi-join stops after confirming existence. Similarly, an anti-join doesn't need to project right-table columns, so it can use efficient NOT IN (subquery) or NOT EXISTS patterns without building large intermediate result sets.

Without semi/anti-join thinking, you either (a) overwrite semantics with unnecessary `DISTINCT` operations, (b) incorrectly lose rows because a `LEFT JOIN` with `WHERE right_id IS NULL` can filter out left rows if the join key itself is nullable, or (c) suffer performance degradation when the right table is large and has high cardinality on the join key.

## Practice

**Problem:** List all job postings that have *never* been posted from a work-from-home location, along with their title and salary. Return each posting exactly once.

```sql
SELECT 
  jp.job_id,
  jp.job_title_short,
  jp.salary_year_avg
FROM job_postings_fact jp
WHERE NOT EXISTS (
  SELECT 1
  FROM job_postings_fact jp_wfh
  WHERE jp_wfh.job_id = jp.job_id
    AND jp_wfh.job_work_from_home = TRUE
)
ORDER BY jp.job_id;
```

Alternatively, using anti-join with NOT IN (works here because job_id is NOT NULL):

```sql
SELECT 
  job_id,
  job_title_short,
  salary_year_avg
FROM job_postings_fact
WHERE job_id NOT IN (
  SELECT job_id
  FROM job_postings_fact
  WHERE job_work_from_home = TRUE
)
ORDER BY job_id;
```

## Notes

- **NOT IN vs NOT EXISTS:** NOT IN silently fails if the subquery contains NULL (the result becomes unknown); NOT EXISTS is NULL-safe and generally more reliable. Prefer NOT EXISTS in production.
- **Semi-join using IN:** `WHERE id IN (SELECT id FROM other_table)` is a semi-join; it stops checking the subquery after finding one match and avoids Cartesian explosion.
- **Row multiplication trap:** If you use `LEFT JOIN ... WHERE right_id IS NOT NULL`, you get all matching pairs, not existence. Use semi-join (IN / EXISTS) or explicit COUNT(*) > 0 to avoid duplicates.
- **Query plan inspection:** Most modern optimizers convert semi/anti-joins to efficient single-pass scans; verify with `EXPLAIN` that the planner isn't materializing the subquery or doing unnecessary sorts.
- **UNION as semi-join:** Sometimes `SELECT ... UNION SELECT ...` replaces a semi-join; confirm cardinality and indexed paths before defaulting to UNION.
