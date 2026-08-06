---
date: 2026-07-25
phase: sql
topic: Recursive CTEs for tree traversal
---

# Recursive CTEs for tree traversal

*SQL for analytics and engineering*

## Concept

WITH RECURSIVE: anchor term seeds the result; recursive term joins back to the CTE itself; UNION ALL combines both. Terminates when the recursive term produces no new rows. Classic uses: org charts, date spines, graph traversal.

## Practice

See `exercises/17_recursive_cte.sql` for worked exercises.

## Solution

```sql
-- See exercises/17_recursive_cte.sql
```

## Notes

- Covered as part of initial SQL exercises.
