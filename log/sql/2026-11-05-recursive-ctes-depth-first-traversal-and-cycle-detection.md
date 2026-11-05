---
date: 2026-11-05
phase: sql
topic: Recursive CTEs: depth-first traversal and cycle detection
---

# Recursive CTEs: depth-first traversal and cycle detection

*SQL for analytics and engineering*

## Concept

A recursive CTE (WITH RECURSIVE) allows you to traverse hierarchical or graph-like data by starting with a base case and iteratively building results. Depth-first traversal means visiting parent → child → grandchild in a single branch before backtracking, useful for organizational hierarchies, category trees, or skill prerequisite chains. Without recursion, you'd either hit a hard limit (e.g., you can only JOIN up to N levels) or resort to expensive application-side loops.

Cycle detection is critical because a malformed hierarchy—where node A points to B, B points back to A—causes infinite loops in recursive queries. SQL engines do not automatically detect cycles; the query will run until it hits a resource limit or depth threshold (typically 100 iterations). You must explicitly track visited nodes using a set or path array, and filter rows where the current node already appears in the traversal chain.

Depth-first order matters for interview answers: a recursive CTE naturally produces depth-first results when you aggregate or order by depth/level, and you reason about it in terms of the recursion tree, not the final result set ordering.

## Practice

**Problem:** Given a table of job categories with parent–child relationships, find all job postings under a given category and its descendants. Return the full traversal path and detect if the hierarchy has cycles.

```sql
-- Assume: job_categories(category_id, category_name, parent_category_id)
-- Goal: Fetch all postings under "Engineering" and its subcategories; halt on cycles

WITH RECURSIVE category_tree AS (
  -- Base: start with the root category
  SELECT
    category_id,
    category_name,
    parent_category_id,
    1 AS depth,
    ARRAY[category_id] AS path,
    FALSE AS has_cycle
  FROM job_categories
  WHERE category_name = 'Engineering'

  UNION ALL

  -- Recursive: descend to children
  SELECT
    jc.category_id,
    jc.category_name,
    jc.parent_category_id,
    ct.depth + 1,
    ct.path || jc.category_id,
    jc.category_id = ANY(ct.path) AS has_cycle
  FROM job_categories jc
  INNER JOIN category_tree ct ON jc.parent_category_id = ct.category_id
  WHERE ct.depth < 10  -- Depth limit as safety
    AND NOT (jc.category_id = ANY(ct.path))  -- Cycle detection: stop if child already in path
)
SELECT
  ct.category_id,
  ct.category_name,
  ct.depth,
  ct.path,
  jpf.job_id,
  jpf.job_title_short,
  jpf.salary_year_avg
FROM category_tree ct
LEFT JOIN job_postings_fact jpf ON ct.category_id = jpf.category_id
WHERE NOT ct.has_cycle
ORDER BY ct.depth, ct.category_id, jpf.job_id;
```

## Notes

- **Cycle detection must be explicit:** Use `ARRAY[node_id]` or a string path, check `node_id = ANY(path)` before recursing, or use a visited set. Missing this causes runaway queries.
- **Depth limit is a safety valve:** Always include `WHERE ct.depth < N` to prevent accidental infinite loops in production; N depends on your data (10–100 is typical).
- **UNION ALL, not UNION:** UNION removes duplicates and kills performance; recursive CTEs almost always use UNION ALL.
- **Adjacent topics:** Tree traversal (breadth-first with a queue simulation), graph algorithms (shortest path, topological sort), and window functions (lead/lag for parent–child comparisons) all interlock with recursive thinking.
- **Interview tip:** Explain your cycle detection logic aloud; mention the depth limit and why it matters; reason about whether DFS or BFS fits the problem before writing.
