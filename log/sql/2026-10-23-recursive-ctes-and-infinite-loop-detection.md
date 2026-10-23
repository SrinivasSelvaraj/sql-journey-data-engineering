---
date: 2026-10-23
phase: sql
topic: Recursive CTEs and infinite loop detection
---

# Recursive CTEs and infinite loop detection

*SQL for analytics and engineering*

## Concept

A recursive CTE (WITH RECURSIVE) in SQL builds result sets iteratively by anchoring an initial query, then repeatedly applying a recursive term until no new rows are produced. This is essential for hierarchical data—organizational charts, category trees, bill-of-materials—and path problems where depth is unknown at query time. Without recursion, you're forced to self-join a fixed number of times, hardcoding hierarchy depth and missing deeper branches.

Infinite loops occur when the recursive term never stops producing new rows. This happens when your termination condition is missing or logically broken—for example, if you forget to increment a depth counter, or if your join condition permits cycles (A → B → A). Most databases guard against this with a built-in recursion limit (often 100 or 1000 iterations), but you'll hit that limit and get an error rather than a silent hang. Prevention is simpler than debugging: always include an explicit depth/iteration counter and validate your join logic prevents cycles.

The performance cost is real. Recursive CTEs materialize intermediate result sets at each iteration, so deeply nested hierarchies can balloon memory use and CPU time. Query plans often show a CTE Scan feeding back into itself. Indexing the join columns, filtering early in the anchor, and capping recursion depth explicitly (UNION ALL vs UNION, and WHERE recursion_depth < N) all matter.

## Practice

**Problem:** Find all job postings within 2 degrees of separation from "Data Engineer" roles—meaning the original posting plus any posting by a company that also hired for that role in the same location.

```sql
WITH RECURSIVE job_chain AS (
  -- Anchor: start with Data Engineer postings
  SELECT 
    job_id,
    job_title_short,
    job_location,
    salary_year_avg,
    1 AS degree
  FROM job_postings_fact
  WHERE job_title_short = 'Data Engineer'
  
  UNION ALL
  
  -- Recursive term: find postings by the same company in the same location
  SELECT 
    jp.job_id,
    jp.job_title_short,
    jp.job_location,
    jp.salary_year_avg,
    jc.degree + 1
  FROM job_postings_fact jp
  INNER JOIN job_chain jc
    ON jp.job_location = jc.job_location
    AND jp.job_id != jc.job_id  -- prevent cycles
  WHERE jc.degree < 2  -- cap recursion depth
)
SELECT DISTINCT
  job_id,
  job_title_short,
  job_location,
  salary_year_avg,
  degree
FROM job_chain
ORDER BY degree, job_location, salary_year_avg DESC;
```

## Notes

- **Forgetting the depth counter:** Always add an incrementing column (degree, level, iteration) and filter it in the WHERE clause of the recursive term. Without it, you have no safe exit condition.
- **Cycle detection:** Use inequality or unique-key checks (job_id != previous_id) to avoid revisiting nodes. For DAGs, consider maintaining a path array or set.
- **UNION vs UNION ALL:** UNION de-duplicates and can mask infinite loops by stopping early; UNION ALL is faster and forces you to rely on your WHERE clause. Use UNION ALL + explicit termination.
- **Query plan inspection:** Look for CTE Scan → Nested Loop → CTE Scan patterns. High iteration counts signal either deep hierarchies (expected) or a logic bug (investigate).
- **Adjacent topics:** Window functions (ROW_NUMBER() OVER (ORDER BY...)) solve some hierarchy problems more efficiently; graph databases handle complex relationships better than recursive SQL at scale.
