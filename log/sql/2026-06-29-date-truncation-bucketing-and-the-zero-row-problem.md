---
date: 2026-06-29
phase: sql
topic: Date truncation, bucketing and the zero-row problem
---

# Date truncation, bucketing and the zero-row problem

*SQL for analytics and engineering*

## Concept

DATE_TRUNC('month', ts) floors to the start of that period. Zero-row problem: if no events exist in a bucket, GROUP BY produces no row — need a date spine LEFT JOINed to fill the gaps.

## Practice

See `exercises/10_date_functions.sql` for worked exercises.

## Solution

```sql
-- See exercises/10_date_functions.sql
```

## Notes

- Covered as part of initial SQL exercises.
