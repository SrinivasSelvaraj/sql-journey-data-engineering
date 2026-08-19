---
date: 2026-08-19
phase: sql
topic: LeetCode 577: Employee Bonus
---

# LeetCode 577: Employee Bonus

*SQL Practice — Easy*

## Problem

Report the name and bonus of each employee with a bonus under 1000 (or no bonus).

## Solution

```sql
SELECT e.name, b.bonus
FROM Employee e
LEFT JOIN Bonus b ON e.empId = b.empId
WHERE b.bonus < 1000
   OR b.bonus IS NULL;
```

## Notes

- LEFT JOIN includes employees with no bonus entry (NULL bonus)
- OR b.bonus IS NULL is the key — WHERE b.bonus < 1000 alone drops NULLs
- COALESCE(b.bonus, 0) < 1000 is an alternative that treats missing as zero
