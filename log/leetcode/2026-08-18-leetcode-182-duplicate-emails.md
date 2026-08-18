---
date: 2026-08-18
phase: sql
topic: LeetCode 182: Duplicate Emails
---

# LeetCode 182: Duplicate Emails

*SQL Practice — Easy*

## Problem

Find all duplicate email addresses.

## Solution

```sql
SELECT email AS Email
FROM Person
GROUP BY email
HAVING COUNT(*) > 1;
```

## Notes

- HAVING filters after GROUP BY — cannot use WHERE COUNT(*) > 1
- If you need the rows themselves, self-join or window ROW_NUMBER
- COUNT(DISTINCT email) would give total unique count, not what we want
