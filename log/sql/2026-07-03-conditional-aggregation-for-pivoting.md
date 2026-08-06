---
date: 2026-07-03
phase: sql
topic: Conditional aggregation for pivoting
---

# Conditional aggregation for pivoting

*SQL for analytics and engineering*

## Concept

SUM(CASE WHEN col = 'x' THEN val END) pivots without extensions. The FILTER clause is cleaner: SUM(val) FILTER (WHERE col = 'x'). Works anywhere an aggregate is valid.

## Practice

See `exercises/20_pivot_crosstab.sql` for worked exercises.

## Solution

```sql
-- See exercises/20_pivot_crosstab.sql
```

## Notes

- Covered as part of initial SQL exercises.
