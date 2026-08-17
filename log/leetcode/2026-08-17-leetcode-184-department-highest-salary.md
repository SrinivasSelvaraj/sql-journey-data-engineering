---
date: 2026-08-17
phase: sql
topic: LeetCode 184: Department Highest Salary
---

# LeetCode 184: Department Highest Salary

*SQL Practice — Medium*

## Problem

Find employees who have the highest salary in each department.

## Solution

```sql
SELECT d.name AS Department,
       e.name AS Employee,
       e.salary AS Salary
FROM Employee e
JOIN Department d ON e.departmentId = d.id
WHERE (e.departmentId, e.salary) IN (
    SELECT departmentId, MAX(salary)
    FROM Employee
    GROUP BY departmentId
);
```

## Notes

- Tuple IN subquery is clean and handles ties naturally
- Alternatively use a window: WHERE DENSE_RANK() OVER (...) = 1
- Watch for departments with no employees if using INNER JOIN
