---
date: 2026-07-21
phase: sql
topic: UNION vs UNION ALL and the cost of deduplication
---

# UNION vs UNION ALL and the cost of deduplication

*SQL for analytics and engineering*

## Concept

UNION sorts and deduplicates — O(n log n) or a hash. UNION ALL just concatenates — O(n). Always use UNION ALL unless you actually need dedup. INTERSECT and EXCEPT also deduplicate implicitly.

## Practice

See `exercises/16_set_operations.sql` for worked exercises.

## Solution

```sql
-- See exercises/16_set_operations.sql
```

## Notes

- Covered as part of initial SQL exercises.
