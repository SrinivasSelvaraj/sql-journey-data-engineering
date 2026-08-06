---
date: 2026-06-07
phase: sql
topic: GROUP BY, HAVING and the order of logical evaluation
---

# GROUP BY, HAVING and the order of logical evaluation

*SQL for analytics and engineering*

## Concept

Logical order: FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY. HAVING filters after aggregation; WHERE filters before — can't use aggregate aliases in WHERE.

## Practice

See `exercises/02_group_by_and_having.sql` for worked exercises.

## Solution

```sql
-- See exercises/02_group_by_and_having.sql
```

## Notes

- Covered as part of initial SQL exercises.
