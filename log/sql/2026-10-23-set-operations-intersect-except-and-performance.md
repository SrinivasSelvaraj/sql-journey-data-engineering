---
date: 2026-10-23
phase: sql
topic: Set operations: intersect, except and performance
---

# Set operations: intersect, except and performance

*SQL for analytics and engineering*

## Concept

Set operations (`INTERSECT`, `EXCEPT`, `UNION`) combine results from multiple queries by treating rows as set members rather than ordered records. `INTERSECT` returns only rows appearing in *both* queries; `EXCEPT` returns rows in the first query but *not* in the second. Both require column-compatible SELECT lists and are useful for finding overlap, exclusions, or differences across logical groups without explicit JOINs.

Performance matters because set operations typically require deduplication and sorting. `INTERSECT` and `EXCEPT` both use `DISTINCT` semantics by default—each incurs a sort or hash aggregation. When you have large result sets from expensive subqueries, the deduplication cost compounds. Using `INTERSECT ALL` or `EXCEPT ALL` skips deduplication if duplicates are acceptable, often providing significant speedup. Understanding the query plan (does it hash or sort? which side is probed?) is essential for optimization.

Set operations break when: (1) column counts don't match, (2) data types are incompatible without implicit cast, (3) you forget that `EXCEPT` is directional (order matters), or (4) you don't account for NULL handling—most databases treat NULL = NULL as false in set operations, so NULLs on both sides may not intersect as expected.

## Practice

**Problem:** Find job titles that appear *both* in remote roles (job_work_from_home = true) *and* in on-site roles (job_work_from_home = false). You want to identify skills/roles that exist in both modalities.

```sql
SELECT DISTINCT job_title_short
FROM job_postings_fact
WHERE job_work_from_home = true

INTERSECT

SELECT DISTINCT job_title_short
FROM job_postings_fact
WHERE job_work_from_home = false;
```

Alternative (often faster for large tables—avoids two full scans + dedup):
```sql
SELECT job_title_short
FROM job_postings_fact
GROUP BY job_title_short
HAVING 
  SUM(CASE WHEN job_work_from_home = true THEN 1 ELSE 0 END) > 0
  AND SUM(CASE WHEN job_work_from_home = false THEN 1 ELSE 0 END) > 0;
```

## Notes

- **Set operations are directional**: `EXCEPT` returns rows in the first query minus the second; reversing the order flips the result. `INTERSECT` and `UNION` are symmetric.
- **NULL semantics vary slightly** across databases; in standard SQL, `INTERSECT` treats NULL as a distinct value that can match another NULL, but verify your engine's behavior.
- **Deduplication is implicit** with `INTERSECT` and `EXCEPT`—use `ALL` suffix to preserve duplicates and skip the costly dedup phase if your use case permits.
- **Consider aggregation or window functions** as an alternative; a single-table GROUP BY with conditional aggregation often outperforms two subqueries + set operation, especially on joined or filtered data.
- **Query plan inspection is critical**: check whether the optimizer is hashing or sorting each side and whether it's using a merge or hash dedup strategy; a poorly chosen plan can make set operations significantly slower than equivalent JOIN-based logic.
