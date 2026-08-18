---
date: 2026-08-18
phase: sql
topic: LeetCode 262: Trips and Users
---

# LeetCode 262: Trips and Users

*SQL Practice — Hard*

## Problem

Compute the cancellation rate for unbanned users between 2013-10-01 and 2013-10-03.

## Solution

```sql
SELECT t.request_at AS Day,
       ROUND(
           SUM(CASE WHEN t.status != 'completed' THEN 1.0 ELSE 0 END)
           / COUNT(*),
       2) AS 'Cancellation Rate'
FROM Trips t
JOIN Users u1 ON t.client_id  = u1.users_id AND u1.banned = 'No'
JOIN Users u2 ON t.driver_id  = u2.users_id AND u2.banned = 'No'
WHERE t.request_at BETWEEN '2013-10-01' AND '2013-10-03'
GROUP BY t.request_at;
```

## Notes

- Both client and driver must be unbanned — two separate joins to Users
- ROUND(..., 2) required by the problem — confirm rounding vs truncation
- Use 1.0 not 1 in CASE to force float division in integer-typed columns
