---
date: 2026-06-12
phase: sql
topic: Correlated subqueries and when the optimiser rewrites them
---

# Correlated subqueries and when the optimiser rewrites them

*SQL for analytics and engineering*

## Concept

A correlated subquery references the outer query's rows — runs once per outer row in the naive plan. Most optimisers rewrite them to JOINs. EXISTS is often cheaper than IN on large sets.

## Practice

See `exercises/04_subqueries.sql` for worked exercises.

## Solution

```sql
-- See exercises/04_subqueries.sql
```

## Notes

- Covered as part of initial SQL exercises.
