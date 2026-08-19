---
date: 2026-08-19
phase: sql
topic: LeetCode 574: Winning Candidate
---

# LeetCode 574: Winning Candidate

*SQL Practice — Medium*

## Problem

Find the name of the candidate who won the election (most votes).

## Solution

```sql
SELECT name
FROM Candidate
WHERE id = (
    SELECT candidateId
    FROM Vote
    GROUP BY candidateId
    ORDER BY COUNT(*) DESC
    LIMIT 1
);
```

## Notes

- ORDER BY COUNT(*) DESC LIMIT 1 picks the top vote-getter
- Assumes no tie for first; add tiebreaker logic if needed
- Window version: RANK() OVER (ORDER BY vote_count DESC) = 1 after a CTE
