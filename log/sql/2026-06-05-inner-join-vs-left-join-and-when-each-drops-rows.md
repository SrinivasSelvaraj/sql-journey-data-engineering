---
date: 2026-06-05
phase: sql
topic: INNER JOIN vs LEFT JOIN and when each drops rows
---

# INNER JOIN vs LEFT JOIN and when each drops rows

*SQL for analytics and engineering*

## Concept

INNER loses unmatched rows on both sides; LEFT keeps all left rows, NULLs on right. Key gotcha: filtering the right table in WHERE silently turns LEFT JOIN into INNER JOIN — use ON instead.

## Practice

See `exercises/03_joins.sql` for worked exercises.

## Solution

```sql
-- See exercises/03_joins.sql
```

## Notes

- Covered as part of initial SQL exercises.
