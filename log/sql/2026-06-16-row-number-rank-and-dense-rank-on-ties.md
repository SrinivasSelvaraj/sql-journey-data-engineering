---
date: 2026-06-16
phase: sql
topic: ROW_NUMBER, RANK and DENSE_RANK on ties
---

# ROW_NUMBER, RANK and DENSE_RANK on ties

*SQL for analytics and engineering*

## Concept

ROW_NUMBER: always unique, arbitrary on ties. RANK: gaps after ties (1,1,3). DENSE_RANK: no gaps (1,1,2). Use RANK for competitions, DENSE_RANK when gap-free numbering matters.

## Practice

See `exercises/06_window_functions.sql` for worked exercises.

## Solution

```sql
-- See exercises/06_window_functions.sql
```

## Notes

- Covered as part of initial SQL exercises.
