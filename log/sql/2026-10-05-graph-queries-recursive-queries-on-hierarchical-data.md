---
date: 2026-10-05
phase: sql
topic: Graph queries: recursive queries on hierarchical data
---

# Graph queries: recursive queries on hierarchical data

*SQL for analytics and engineering*

## Concept

Recursive queries (Common Table Expressions with `WITH RECURSIVE`) traverse hierarchical or graph-structured data where rows reference other rows in the same table. They're essential for org charts, category hierarchies, bill-of-materials trees, and path-finding problems. Each recursion step builds on the previous one: an anchor query seeds the result set, then the recursive member joins back to the CTE to extend it one level deeper until no new rows match.

Without recursive queries, you'd need application logic to loop through multiple queries or denormalize your data heavily. This becomes impractical for unknown tree depth and creates maintenance nightmares. Recursive CTEs keep logic declarative and let the optimizer reason about termination.

Performance depends critically on: (1) filtering the anchor query as tightly as possible, (2) indexing the join columns, and (3) understanding that depth-first recursion can explode in row count if cycles exist. Always add a safeguard (e.g., `WHERE depth < 10`) and check query plans for full table scans at each recursion level.

## Practice

**Problem:** A job posting dataset records manager relationships: each job posting can have a `manager_job_id` that points to another row. Find all subordinate roles (direct and indirect) reporting to the Senior Data Engineer job #1001, including salary and work-from-home status. Return each role with its hierarchy depth.

```sql
WITH RECURSIVE reporting_chain AS (
  -- Anchor: start with the manager
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_id AS manager_job_id,
    0 AS depth
  FROM job_postings_fact
  WHERE job_id = 1001

  UNION ALL

  -- Recursive: find all direct reports of people already in the chain
  SELECT 
    j.job_id,
    j.job_title_short,
    j.salary_year_avg,
    j.job_work_from_home,
    rc.job_id,
    rc.depth + 1
  FROM job_postings_fact j
  INNER JOIN reporting_chain rc
    ON j.manager_job_id = rc.job_id
  WHERE rc.depth < 10  -- Prevent infinite loops
)
SELECT 
  depth,
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home
FROM reporting_chain
ORDER BY depth, job_id;
```

## Notes

- **Cycle detection:** If your graph can have cycles (A → B → A), the `WHERE depth < max_depth` guard is mandatory. Without it, recursion never terminates and queries hang. Real hierarchies rarely have cycles, but malformed data does.

- **Anchor vs. recursive member:** The anchor query must return rows; the recursive member extends them. Mixing filtering into only the anchor (or only the recursive part) is a common mistake that produces incomplete results.

- **Index strategy:** Create indexes on the foreign-key column (e.g., `manager_job_id`) and the primary key. The recursive join repeatedly searches for children, so poor indexing causes full table scans at each level.

- **Row explosion:** Each recursion level can multiply row count. Always check the actual row count returned; if depth 5 returns 10M rows, you likely have a Cartesian product in your join or missing a WHERE condition.

- **Alternatives to know:** Window functions with `ROW_NUMBER() OVER (ORDER BY ...)` work for single-pass hierarchies; materialized path columns (storing the full ancestor string) avoid recursion entirely but sacrifice flexibility on updates.
