---
date: 2026-08-19
phase: sql
topic: LeetCode 596: Classes More than 5 Students
---

# LeetCode 596: Classes More than 5 Students

*SQL Practice — Easy*

## Problem

Find all classes that have at least 5 students.

## Solution

```sql
SELECT class
FROM Courses
GROUP BY class
HAVING COUNT(student) >= 5;
```

## Notes

- COUNT(student) counts non-NULL students; COUNT(*) also works here
- HAVING filters groups after aggregation — cannot use WHERE for this
- Simple GROUP BY + HAVING is the canonical pattern for 'at least N rows per group'
