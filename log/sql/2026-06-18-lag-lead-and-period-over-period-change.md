---
date: 2026-06-18
phase: sql
topic: LAG, LEAD and period-over-period change
---

# LAG, LEAD and period-over-period change

*SQL for analytics and engineering*

## Concept

LAG(col, n) gets the value n rows before; LEAD(col, n) gets n rows after. Default offset is 1. Third argument is the fill value when at the boundary. Useful for MoM/WoW/YoY comparisons.

## Practice

See `exercises/06_window_functions.sql` for worked exercises.

## Solution

```sql
-- See exercises/06_window_functions.sql
```

## Notes

- Covered as part of initial SQL exercises.
