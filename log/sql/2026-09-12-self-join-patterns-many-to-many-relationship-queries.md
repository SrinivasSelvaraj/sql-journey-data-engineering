---
date: 2026-09-12
phase: sql
topic: Self-join patterns: many-to-many relationship queries
---

# Self-join patterns: many-to-many relationship queries

*SQL for analytics and engineering*

## Concept

A self-join connects a table to itself to model relationships *within* the same entity set. Many-to-many self-joins are especially valuable when you need to find pairs, groups, or comparative relationships—for example, matching similar jobs, finding competing candidates, or identifying related records without a separate junction table.

The key insight: treating the same table as two logical entities (often aliased as `a` and `b`) lets you express "give me all pairs where condition X holds." Without self-joins, you'd either miss these relationships or materialize them in preprocessing. Many-to-many patterns break when you forget to handle:
- **Duplicate pairs** (both `(A,B)` and `(B,A)` appearing when you want only one)
- **Self-matches** (a record matching itself when it shouldn't)
- **Cartesian explosion** (joining all rows to all rows without proper filtering, ballooning result sets)

Self-joins are critical for analytics because they reveal competitive landscapes, recommend similar items, or detect anomalies—all without external data.

## Practice

**Problem:** Find all pairs of jobs with the same title but different salary ranges (salary differs by >$30k). Return job_id pairs, title, and the salary difference, ordered by largest difference first. Exclude same-job matches and duplicate pairs.

```sql
SELECT
  a.job_id AS job_id_1,
  b.job_id AS job_id_2,
  a.job_title_short,
  a.salary_year_avg AS salary_1,
  b.salary_year_avg AS salary_2,
  ABS(a.salary_year_avg - b.salary_year_avg) AS salary_diff
FROM job_postings_fact a
INNER JOIN job_postings_fact b
  ON a.job_title_short = b.job_title_short
  AND a.job_id < b.job_id  -- prevents duplicate pairs and self-matches
  AND ABS(a.salary_year_avg - b.salary_year_avg) > 30000
WHERE a.salary_year_avg IS NOT NULL
  AND b.salary_year_avg IS NOT NULL
ORDER BY salary_diff DESC;
```

## Notes

- **The `<` or `>` trick:** Use `a.job_id < b.job_id` (or any unique identifier) to avoid symmetric duplicates and eliminate self-matches in one condition. This is far cheaper than `DISTINCT`.
- **NULL handling:** Self-joins often amplify NULL issues. Explicitly filter `WHERE a.col IS NOT NULL AND b.col IS NOT NULL` before the join or within the ON clause to avoid silent data loss.
- **Query plan awareness:** Self-joins require two table scans (or one scan + hash/merge). Check EXPLAIN output—if you see a Cartesian product before filtering, push your join condition earlier or add indexes on join keys.
- **Adjacent concept:** Self-joins are the foundation for window functions with PARTITION BY or LAG/LEAD, and for recursive CTEs. Mastering the logic here transfers directly.
- **Revisit:** Test with small datasets first; self-joins can explode row counts dramatically. Use LIMIT or COUNT(*) before committing to full result retrieval.
