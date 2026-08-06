---
date: 2026-07-29
phase: sql
topic: Transactions, isolation levels and lost updates
---

# Transactions, isolation levels and lost updates

*SQL for analytics and engineering*

## Concept

READ COMMITTED (default in PG): sees committed rows only, but two SELECTs in one txn can see different data. REPEATABLE READ: consistent snapshot throughout. SERIALIZABLE: full isolation, higher conflict rate. Lost update happens when two txns read then write the same row — use SELECT FOR UPDATE or optimistic locking.

## Practice

See `exercises/15_transactions.sql` for worked exercises.

## Solution

```sql
-- See exercises/15_transactions.sql
```

## Notes

- Covered as part of initial SQL exercises.
