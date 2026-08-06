---
date: 2026-07-17
phase: sql
topic: Index design and column order
---

# Index design and column order

*SQL for analytics and engineering*

## Concept

Composite index (a, b, c) can satisfy queries on a, (a,b), (a,b,c) — not b alone. Put the highest-selectivity or equality column first. Partial indexes (WHERE condition) are smaller and faster for filtered queries.

## Practice

See `exercises/14_indexes_and_performance.sql` for worked exercises.

## Solution

```sql
-- See exercises/14_indexes_and_performance.sql
```

## Notes

- Covered as part of initial SQL exercises.
