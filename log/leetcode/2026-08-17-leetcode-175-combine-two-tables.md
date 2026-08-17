---
date: 2026-08-17
phase: sql
topic: LeetCode 175: Combine Two Tables
---

# LeetCode 175: Combine Two Tables

*SQL Practice — Easy*

## Problem

Report the first name, last name, city, and state of each person. If address is missing, report NULL.

## Solution

```sql
SELECT p.firstName, p.lastName, a.city, a.state
FROM Person p
LEFT JOIN Address a ON p.personId = a.personId;
```

## Notes

- LEFT JOIN is required — INNER JOIN drops persons with no address
- NULL propagates naturally when the right side has no match
- Classic intro to outer join semantics
