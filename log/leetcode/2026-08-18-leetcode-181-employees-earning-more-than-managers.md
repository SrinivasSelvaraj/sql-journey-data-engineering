---
date: 2026-08-18
phase: sql
topic: LeetCode 181: Employees Earning More Than Their Managers
---

# LeetCode 181: Employees Earning More Than Their Managers

*SQL Practice — Easy*

## Problem

Find employees who earn more than their managers.

## Solution

```sql
SELECT e.name AS Employee
FROM Employee e
JOIN Employee m ON e.managerId = m.id
WHERE e.salary > m.salary;
```

## Notes

- Self-join: alias both sides to distinguish employee from manager
- NULL managerId (CEO) is excluded by the INNER JOIN — intended
- Could also use a correlated subquery but the join is more readable
