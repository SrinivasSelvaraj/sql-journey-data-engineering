---
date: 2026-08-18
phase: sql
topic: LeetCode 197: Rising Temperature
---

# LeetCode 197: Rising Temperature

*SQL Practice — Easy*

## Problem

Find all dates where the temperature is higher than the previous day.

## Solution

```sql
SELECT w1.id
FROM Weather w1
JOIN Weather w2
  ON DATEDIFF(w1.recordDate, w2.recordDate) = 1
WHERE w1.temperature > w2.temperature;
```

## Notes

- DATEDIFF(a, b) = 1 means a is exactly one day after b
- LAG alternative: LAG(temperature) OVER (ORDER BY recordDate)
- Watch for duplicate dates — they can cause unexpected cartesian results
