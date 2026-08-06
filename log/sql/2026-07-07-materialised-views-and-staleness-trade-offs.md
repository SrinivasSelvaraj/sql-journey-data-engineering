---
date: 2026-07-07
phase: sql
topic: Materialised views and staleness trade-offs
---

# Materialised views and staleness trade-offs

*SQL for analytics and engineering*

## Concept

A view reruns its query on every access. A materialised view stores the result — fast reads, but stale until REFRESH MATERIALIZED VIEW. CONCURRENTLY refreshes without locking reads (needs a unique index).

## Practice

See `exercises/11_views.sql` for worked exercises.

## Solution

```sql
-- See exercises/11_views.sql
```

## Notes

- Covered as part of initial SQL exercises.
