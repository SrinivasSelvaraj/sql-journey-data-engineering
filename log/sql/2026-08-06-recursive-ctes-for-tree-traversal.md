---
date: 2026-08-06
phase: sql
topic: Recursive CTEs for tree traversal
---

# Recursive CTEs for tree traversal

*SQL for analytics and engineering*

## Concept

A recursive CTE (WITH RECURSIVE) in SQL enables traversal of hierarchical or graph-structured data by iteratively applying the same logic until a stopping condition is met. The CTE has two parts: an anchor query that establishes the base case, and a recursive query that references the CTE itself, each iteration building on the previous result set. This is essential for problems like org charts, file system paths, bill-of-materials hierarchies, or social network connections where data relationships nest multiple levels deep and you can't know the depth in advance.

Without recursive CTEs, you'd be forced into either application-layer loops (expensive and error-prone), self-joins N times (unmaintainable and inflexible), or storing denormalized path columns (brittle and hard to update). Recursive CTEs keep the logic declarative and let the database engine handle iteration, making them crucial for interview settings where you need clean, testable SQL that scales across unknown depths.

The key constraint is the `UNION ALL` between anchor and recursive parts—this prevents premature termination and ensures all paths are explored. Most databases (PostgreSQL, MySQL 8.0+, SQL Server, Snowflake, BigQuery) support it, though some impose recursion depth limits for safety.

## Practice

**Problem:** Given a flat job posting table, imagine a scenario where you need to model job progression hierarchies (e.g., "Data Analyst" → "Senior Data Analyst" → "Lead Data Analyst"). Create a recursive CTE that, starting from entry-level data analyst roles, finds all successor roles and counts how many postings exist at each level in the career ladder.

Assume an additional table `job_progression(from_job_title, to_job_title)` exists.

```sql
WITH RECURSIVE career_ladder AS (
  -- Anchor: start with entry-level data analyst roles
  SELECT
    job_title_short,
    1 AS level,
    COUNT(*) AS postings_count
  FROM job_postings_fact
  WHERE job_title_short LIKE '%Data Analyst%'
    AND job_title_short NOT LIKE '%Senior%'
    AND job_title_short NOT LIKE '%Lead%'
  GROUP BY job_title_short
  
  UNION ALL
  
  -- Recursive: find the next level in progression
  SELECT
    jp.to_job_title,
    cl.level + 1,
    COUNT(jpf.job_id)
  FROM career_ladder cl
  INNER JOIN job_progression jp ON cl.job_title_short = jp.from_job_title
  INNER JOIN job_postings_fact jpf ON jp.to_job_title = jpf.job_title_short
  WHERE cl.level < 5  -- Prevent infinite recursion
  GROUP BY jp.to_job_title, cl.level + 1
)
SELECT
  level,
  job_title_short,
  postings_count
FROM career_ladder
ORDER BY level, postings_count DESC;
```

## Notes

- **Stop condition is critical:** Always include a termination clause (e.g., `WHERE depth < max_depth` or `WHERE some_column IS NOT NULL`) to prevent runaway recursion; databases often have built-in limits but queries will fail or time out if logic is faulty.
- **UNION ALL, not UNION:** Use `UNION ALL` to preserve duplicates and allow the same path to be explored from multiple starting points; `UNION` deduplicates and breaks traversal logic.
- **Watch for cycles in graphs:** If the data contains circular references (A→B→C→A), the recursion will loop infinitely unless you track visited nodes; use a path column or visited set to avoid this.
- **Performance tuning:** Recursive CTEs can be expensive on large graphs; consider indexing the join columns heavily, limiting recursion depth, and testing the query plan with `EXPLAIN` to spot sequential scans.
- **Adjacent topics:** Tree structures (parent_id foreign keys), window functions for path aggregation, `STRING_AGG` or array concatenation to build path strings, and breadth-first vs. depth-first traversal strategies (order matters in business logic).
