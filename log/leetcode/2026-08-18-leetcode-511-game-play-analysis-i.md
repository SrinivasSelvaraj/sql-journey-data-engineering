---
date: 2026-08-18
phase: sql
topic: LeetCode 511: Game Play Analysis I
---

# LeetCode 511: Game Play Analysis I

*SQL Practice — Easy*

## Problem

Find the first login date for each player.

## Solution

```sql
SELECT player_id, MIN(event_date) AS first_login
FROM Activity
GROUP BY player_id;
```

## Notes

- MIN(event_date) on a date column gives the earliest date per group
- Alternative: ROW_NUMBER() OVER (PARTITION BY player_id ORDER BY event_date) = 1
- Foundation for the rest of the Game Play Analysis series
