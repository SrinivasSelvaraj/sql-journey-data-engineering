---
date: 2026-08-18
phase: sql
topic: LeetCode 196: Delete Duplicate Emails
---

# LeetCode 196: Delete Duplicate Emails

*SQL Practice — Easy*

## Problem

Delete all duplicate email entries, keeping the row with the smallest id.

## Solution

```sql
DELETE p1
FROM Person p1
JOIN Person p2
  ON p1.email = p2.email
 AND p1.id > p2.id;
```

## Notes

- Deleting with a self-join: keep the row with the smaller id
- MySQL does not allow DELETE with a subquery on the same table — the join is the workaround
- Always test the equivalent SELECT before running DELETE
