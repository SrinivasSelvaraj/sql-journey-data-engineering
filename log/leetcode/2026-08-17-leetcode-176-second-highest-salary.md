---
date: 2026-08-17
phase: sql
topic: LeetCode 176: Second Highest Salary
---

# LeetCode 176: Second Highest Salary

*SQL Practice — Medium*

## Problem

Find the second highest distinct salary. Return NULL if it does not exist.

## Solution

```sql
SELECT MAX(salary) AS SecondHighestSalary
FROM Employee
WHERE salary < (SELECT MAX(salary) FROM Employee);
```

## Notes

- Subquery filters out the maximum before taking the next MAX
- Returns NULL automatically when fewer than 2 distinct salaries exist
- Alternative: DENSE_RANK() OVER (ORDER BY salary DESC) then filter rank = 2
