---
date: 2026-08-17
phase: sql
topic: LeetCode 180: Consecutive Numbers
---

# LeetCode 180: Consecutive Numbers

*SQL Practice — Medium*

## Problem

Find all numbers that appear at least three times consecutively.

## Solution

```sql
SELECT DISTINCT l1.num AS ConsecutiveNums
FROM Logs l1
JOIN Logs l2 ON l2.id = l1.id + 1 AND l2.num = l1.num
JOIN Logs l3 ON l3.id = l1.id + 2 AND l3.num = l1.num;
```

## Notes

- Three-way self-join works because id is sequential with no gaps
- If gaps exist in id, use LAG/LEAD to compare adjacent rows instead
- DISTINCT removes duplicates when the same number repeats more than 3 times
