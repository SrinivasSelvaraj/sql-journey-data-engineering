---
date: 2026-08-18
phase: sql
topic: LeetCode 185: Department Top Three Salaries
---

# LeetCode 185: Department Top Three Salaries

*SQL Practice — Hard*

## Problem

Find employees who earn one of the top three unique salaries in their department.

## Solution

```sql
SELECT d.name AS Department, e.name AS Employee, e.salary AS Salary
FROM Employee e
JOIN Department d ON e.departmentId = d.id
WHERE (
    SELECT COUNT(DISTINCT e2.salary)
    FROM Employee e2
    WHERE e2.departmentId = e.departmentId
      AND e2.salary > e.salary
) < 3;
```

## Notes

- Correlated subquery counts how many distinct salaries are higher
- < 3 means this salary is in the top 3 (0, 1 or 2 salaries above it)
- Window alternative: DENSE_RANK() OVER (PARTITION BY dept ORDER BY salary DESC) <= 3
