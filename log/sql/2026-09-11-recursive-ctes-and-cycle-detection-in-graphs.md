---
date: 2026-09-11
phase: sql
topic: Recursive CTEs and cycle detection in graphs
---

# Recursive CTEs and cycle detection in graphs

*SQL for analytics and engineering*

## Concept

A **recursive CTE** (Common Table Expression) in SQL allows a query to reference itself, enabling hierarchical and graph traversal operations. The recursive structure has two parts: an anchor query (base case) that seeds initial rows, and a recursive query that repeatedly joins against previous results until a termination condition is met. This is essential for problems like org charts, bill-of-materials hierarchies, and graph reachability—situations where depth or relationships are unknown at query time.

**Cycle detection** becomes critical when traversing graphs with potential loops. Without cycle guards, a recursive CTE will either fail with a cycle detection error (PostgreSQL's default behavior) or run indefinitely, consuming memory and CPU. SQL provides explicit mechanisms—typically a `CYCLE` clause or manual tracking via a visited node set—to break infinite loops and return meaningful results even when cycles exist. This is common in real-world scenarios: employee→manager chains with reporting loops, recommendation graphs, and supply chain networks.

Without recursive CTEs, you're limited to hard-coded depth levels (multiple self-joins) or pushing the recursion logic into application code, losing query pushdown and incurring round-trip overhead. With cycles and no detection, queries hang or crash in production, making cycle handling a non-negotiable detail in interview and real-world contexts.

## Practice

**Problem:** Find all job postings reachable from a given job posting through a "related_jobs" edge list (assume a `job_relationships(from_job_id, to_job_id)` table exists). Return the job title, salary, and depth level. Detect and stop at cycles to avoid infinite recursion.

```sql
WITH RECURSIVE job_graph AS (
  -- Anchor: start from job_id = 123
  SELECT 
    from_job_id,
    to_job_id,
    1 AS depth,
    ARRAY[from_job_id, to_job_id] AS path
  FROM job_relationships
  WHERE from_job_id = 123
  
  UNION ALL
  
  -- Recursive: expand frontier, but exclude if target already in path
  SELECT 
    jg.from_job_id,
    jr.to_job_id,
    jg.depth + 1,
    jg.path || jr.to_job_id
  FROM job_graph jg
  INNER JOIN job_relationships jr ON jg.to_job_id = jr.from_job_id
  WHERE jg.depth < 10  -- depth limit to prevent runaway
    AND NOT jr.to_job_id = ANY(jg.path)  -- cycle detection: stop if target is in path
)
SELECT 
  jp.job_id,
  jp.job_title_short,
  jp.salary_year_avg,
  jg.depth,
  jg.path
FROM job_graph jg
INNER JOIN job_postings_fact jp ON jg.to_job_id = jp.job_id
ORDER BY depth, jg.to_job_id;
```

## Notes

- **Manual cycle detection via path array** (as shown) is portable across SQL dialects but can become expensive in deep graphs; PostgreSQL 14+ offers native `CYCLE` clause syntax for cleaner handling.
- **Depth limits are a safety valve**: always include a `WHERE depth < N` condition to prevent runaway recursion, even with cycle detection in place.
- **Array membership checks (`= ANY()`)** work well for moderate depth but scale poorly; for large graphs, consider a temporary visited table or bitset approach.
- **Recursive CTEs are evaluated iteratively, not recursively in the programming sense**: each iteration expands all frontier nodes in parallel, so performance depends on branching factor and depth, not call-stack overhead.
- **Adjacent topics worth revisiting**: graph algorithms (shortest path, topological sort), window functions for hierarchical ranking, and execution plan analysis to spot N+1 join patterns in recursive steps.
