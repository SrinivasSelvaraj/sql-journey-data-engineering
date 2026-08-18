---
date: 2026-08-18
phase: sql
topic: LeetCode 512: Game Play Analysis II
---

# LeetCode 512: Game Play Analysis II

*SQL Practice — Easy*

## Problem

Report the device that each player first logged in on.

## Solution

```sql
SELECT player_id, device_id
FROM Activity
WHERE (player_id, event_date) IN (
    SELECT player_id, MIN(event_date)
    FROM Activity
    GROUP BY player_id
);
```

## Notes

- Tuple IN subquery filters to only the first-login row per player
- Handles ties on the same date correctly if a player logged in from two devices
- Window version: ROW_NUMBER() OVER (PARTITION BY player_id ORDER BY event_date) = 1
