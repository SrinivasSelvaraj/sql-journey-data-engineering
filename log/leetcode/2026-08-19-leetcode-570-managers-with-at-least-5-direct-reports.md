---
date: 2026-08-19
phase: sql
topic: LeetCode 570: Managers with at Least 5 Direct Reports
---

# LeetCode 570: Managers with at Least 5 Direct Reports

*SQL Practice — Medium*

## Problem

Find managers with at least 5 direct reports.

## Solution

```sql
SELECT name
FROM Employee
WHERE id IN (
    SELECT managerId
    FROM Employee
    GROUP BY managerId
    HAVING COUNT(*) >= 5
);
```

## Notes

- Subquery groups by managerId and filters in HAVING — cleaner than a join
- Alternative JOIN: JOIN (subquery) m ON Employee.id = m.managerId
- NULL managerId rows are grouped together — add WHERE managerId IS NOT NULL if needed
