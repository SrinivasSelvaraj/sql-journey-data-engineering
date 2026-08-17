---
date: 2026-08-17
phase: sql
topic: LeetCode 178: Rank Scores
---

# LeetCode 178: Rank Scores

*SQL Practice — Medium*

## Problem

Rank scores with no gaps (DENSE_RANK behaviour). Highest score gets rank 1.

## Solution

```sql
SELECT score,
       DENSE_RANK() OVER (ORDER BY score DESC) AS `rank`
FROM Scores
ORDER BY score DESC;
```

## Notes

- DENSE_RANK skips no numbers on ties, unlike RANK
- Back-ticking `rank` is required in MySQL — it is a reserved word
- ROW_NUMBER would give different ranks for equal scores
