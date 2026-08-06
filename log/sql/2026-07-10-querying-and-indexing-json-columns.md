---
date: 2026-07-10
phase: sql
topic: Querying and indexing JSON columns
---

# Querying and indexing JSON columns

*SQL for analytics and engineering*

## Concept

-> returns JSONB child; ->> returns TEXT. Use jsonb_array_elements_text to explode arrays. GIN index on to_jsonb(col) or a specific path speeds up containment (@>) queries.

## Practice

See `exercises/18_json_operations.sql` for worked exercises.

## Solution

```sql
-- See exercises/18_json_operations.sql
```

## Notes

- Covered as part of initial SQL exercises.
