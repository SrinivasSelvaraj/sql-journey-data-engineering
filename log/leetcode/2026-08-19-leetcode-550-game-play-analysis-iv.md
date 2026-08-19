---
date: 2026-08-19
phase: sql
topic: LeetCode 550: Game Play Analysis IV
---

# LeetCode 550: Game Play Analysis IV

*SQL Practice — Medium*

## Problem

Find the fraction of players who logged in again on the day after their first login.

## Solution

```sql
SELECT ROUND(
    COUNT(DISTINCT a2.player_id) / COUNT(DISTINCT a1.player_id),
    2) AS fraction
FROM (
    SELECT player_id, MIN(event_date) AS first_login
    FROM Activity
    GROUP BY player_id
) a1
LEFT JOIN Activity a2
  ON a1.player_id = a2.player_id
 AND a2.event_date = DATE_ADD(a1.first_login, INTERVAL 1 DAY);
```

## Notes

- Subquery computes the first login per player, then LEFT JOIN checks the next day
- COUNT(DISTINCT) on the joined side counts only players who returned
- Dividing two COUNTs: ensure float division — wrap numerator in CAST or multiply by 1.0 if needed
