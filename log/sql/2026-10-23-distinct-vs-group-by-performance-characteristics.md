---
date: 2026-10-23
phase: sql
topic: DISTINCT vs GROUP BY performance characteristics
---

# DISTINCT vs GROUP BY performance characteristics

*SQL for analytics and engineering*

## Concept

`DISTINCT` and `GROUP BY` both eliminate duplicates, but they differ fundamentally in cost and capability. `DISTINCT` applies to the entire result set after projection—it requires sorting or hashing all columns—while `GROUP BY` aggregates at the row level and only materializes grouped columns plus aggregates. When you need only unique values with no aggregation, `DISTINCT` is simpler; when you need counts, sums, or conditional logic *per group*, `GROUP BY` is necessary.

The performance gap widens with dataset size and cardinality. `DISTINCT SELECT col1, col2, col3` must deduplicate across all three columns, consuming memory proportional to the output width. `GROUP BY col1` produces one row per unique col1 value regardless of how many other columns exist. Query planners often push `DISTINCT` down to index lookups or use streaming hash aggregation, but careless use—especially `DISTINCT *` on wide tables—forces unnecessary I/O and sorting.

Without understanding the distinction, you'll write `SELECT DISTINCT job_title_short FROM job_postings_fact` when you mean `SELECT job_title_short FROM job_postings_fact GROUP BY job_title_short`, wasting CPU on unnecessary columns. Conversely, you'll attempt `SELECT DISTINCT salary_year_avg, COUNT(*) ...` (invalid syntax) instead of reaching for `GROUP BY`.

## Practice

**Problem:** Find the count of unique job titles and the average salary *per* job title, but only for remote positions posted after 2023-01-01. Return the results ordered by average salary descending.

```sql
SELECT 
  job_title_short,
  COUNT(*) AS job_count,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_posted_date > '2023-01-01'
GROUP BY job_title_short
ORDER BY avg_salary DESC;
```

**Why GROUP BY, not DISTINCT:** We need aggregates (`COUNT`, `AVG`) per job title. `DISTINCT` cannot produce counts. `GROUP BY job_title_short` efficiently groups all rows sharing the same title, then computes aggregates within each group.

## Notes

- **Common mistake:** Using `SELECT DISTINCT col1, col2, COUNT(*)` — `DISTINCT` applies to the result *after* aggregation, often producing unexpected output; use `GROUP BY` for aggregation instead.
- **Index leverage:** Query planners may use index-only scans for `GROUP BY` on indexed columns (e.g., `GROUP BY job_title_short`), avoiding table access entirely; `DISTINCT` rarely gets this optimization.
- **NULLs behave identically:** Both `DISTINCT` and `GROUP BY` treat `NULL` as a single distinct/grouped value, so filtering `WHERE col IS NOT NULL` is required if you want to exclude them.
- **Memory and sorting:** Large result sets force disk spilling; `GROUP BY` with streaming hash aggregation (no sort) is generally faster than `DISTINCT` requiring a sort step. Monitor query plans with `EXPLAIN`.
- **Adjacent topics:** `GROUP BY` with `HAVING` (post-aggregation filtering), window functions as an alternative to self-joins for ranking within groups, and `UNION` vs. `UNION ALL` (another deduplication mechanism with different costs).
