---
date: 2026-06-20
phase: sql
topic: Running totals and moving averages
---

# Running totals and moving averages

*SQL for analytics and engineering*

## Concept

SUM(col) OVER (ORDER BY date) gives a running total. Moving average needs a frame: ROWS BETWEEN 6 PRECEDING AND CURRENT ROW. RANGE uses logical (value-based) bounds, ROWS uses physical row count.

## Practice

See `exercises/06_window_functions.sql` for worked exercises.

## Solution

```sql
-- See exercises/06_window_functions.sql
```

## Notes

- Covered as part of initial SQL exercises.
