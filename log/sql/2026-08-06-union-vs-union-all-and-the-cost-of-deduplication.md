---
date: 2026-08-06
phase: sql
topic: UNION vs UNION ALL and the cost of deduplication
---

# UNION vs UNION ALL and the cost of deduplication

*SQL for analytics and engineering*

## Concept

`UNION` removes duplicate rows from the combined result set, while `UNION ALL` keeps all rows. This difference has profound performance implications: `UNION` requires a **sort and deduplication step** (typically a hash aggregate or sort-based operation) on the entire combined dataset, adding CPU and memory cost. `UNION ALL` is a simple concatenation and is nearly free.

Use `UNION` only when you *know* duplicates exist and *must* be eliminated. In analytics and ETL, duplicates often arise from joining multiple data sources or unioning historical snapshots. However, many queries don't actually need deduplication—you're combining disjoint result sets (e.g., two different fact tables filtered by date ranges) where duplicates cannot logically occur. Blindly using `UNION` wastes resources on unnecessary deduplication.

The cost scales with row count and cardinality. Deduplicating 10M rows is orders of magnitude more expensive than deduplicating 100K rows. In interviews and production, reason explicitly: "These two queries cannot produce the same job_id in the same row, so duplicates are impossible—use `UNION ALL`."

## Practice

**Problem:** You need to report all unique job titles offered in either remote positions (work_from_home = TRUE) or positions in "New York, NY". Avoid counting the same job title twice if it appears in both categories. Use `job_postings_fact`.

```sql
SELECT job_title_short
FROM job_postings_fact
WHERE job_work_from_home = TRUE

UNION

SELECT job_title_short
FROM job_postings_fact
WHERE job_location = 'New York, NY'
ORDER BY job_title_short;
```

The `UNION` is correct here because a job posting could theoretically be both remote *and* in New York, so duplicates are possible. If you used `UNION ALL`, "Data Analyst" might appear twice.

## Notes

- **Deduplication cost is hidden:** Query planners don't always show you the sort or hash aggregate in EXPLAIN output; check for "aggregate" or "unique" operations and row count reductions.
- **Implicit assumption in UNION:** Both queries must return the same number and types of columns. Column names come from the first SELECT.
- **NULL handling:** Both `UNION` and `UNION ALL` treat NULL as a distinct value in deduplication; two NULLs are considered equal.
- **Alternative: GROUP BY is sometimes cheaper:** If you `SELECT DISTINCT` or `UNION` a large result set, a pre-filtered `GROUP BY` on the original table may avoid redundant work.
- **Connects to:** set operations (`EXCEPT`, `INTERSECT` also deduplicate), window functions as a non-deduplicating alternative, and query plan reading for cardinality estimation.
