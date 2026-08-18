---
date: 2026-08-18
phase: sql
topic: LeetCode 534: Game Play Analysis III
---

# LeetCode 534: Game Play Analysis III

*SQL Practice — Medium*

## Problem

Report the running total of games played for each player ordered by date.

## Solution

```sql
SELECT player_id,
       event_date,
       SUM(games_played) OVER (
           PARTITION BY player_id
           ORDER BY event_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS games_played_so_far
FROM Activity;
```

## Notes

- Running total = SUM with default window frame UNBOUNDED PRECEDING AND CURRENT ROW
- PARTITION BY restarts the running total for each player
- Cumulative SUM is additive so it works without worrying about semi-additive issues
