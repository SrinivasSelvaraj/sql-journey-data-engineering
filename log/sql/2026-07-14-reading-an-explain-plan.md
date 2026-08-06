---
date: 2026-07-14
phase: sql
topic: Reading an EXPLAIN plan
---

# Reading an EXPLAIN plan

*SQL for analytics and engineering*

## Concept

EXPLAIN shows the planner's estimate. EXPLAIN ANALYZE runs the query and shows actual vs estimated rows. Key nodes: Seq Scan (slow on large tables), Index Scan, Hash Join, Nested Loop. High row-count misestimates cause bad plans.

## Practice

See `exercises/14_indexes_and_performance.sql` for worked exercises.

## Solution

```sql
-- See exercises/14_indexes_and_performance.sql
```

## Notes

- Covered as part of initial SQL exercises.
