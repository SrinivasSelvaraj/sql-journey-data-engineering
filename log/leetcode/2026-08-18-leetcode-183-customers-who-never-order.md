---
date: 2026-08-18
phase: sql
topic: LeetCode 183: Customers Who Never Order
---

# LeetCode 183: Customers Who Never Order

*SQL Practice — Easy*

## Problem

Find customers who never placed an order.

## Solution

```sql
SELECT c.name AS Customers
FROM Customers c
LEFT JOIN Orders o ON c.id = o.customerId
WHERE o.id IS NULL;
```

## Notes

- Anti-join pattern: LEFT JOIN + IS NULL is equivalent to NOT EXISTS
- NOT IN is dangerous if Orders contains NULL customerIds — prefer LEFT JOIN
- EXISTS version: WHERE NOT EXISTS (SELECT 1 FROM Orders WHERE customerId = c.id)
