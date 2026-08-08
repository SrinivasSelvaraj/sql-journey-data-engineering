---
date: 2026-08-08
phase: sql
topic: Transactions, isolation levels and lost updates
---

# Transactions, isolation levels and lost updates

*SQL for analytics and engineering*

## Concept

A **transaction** is a sequence of SQL operations that execute as an atomic unit: either all succeed and commit, or all roll back. **Isolation levels** define how concurrent transactions interact—specifically, which anomalies (dirty reads, non-repeatable reads, phantom reads, lost updates) are allowed. A **lost update** occurs when two concurrent transactions both read the same value, modify it independently, and write back; the second write overwrites the first, losing that change.

Isolation levels matter because the default (READ COMMITTED in PostgreSQL, autocommit in many systems) permits lost updates. In analytics, you often don't need strong isolation, but in ETL pipelines, audit tables, and inventory systems, a lost update can corrupt data—salary budgets incremented twice, but only one increment persists. Without explicit locking or serializable isolation, concurrent updates to shared counters or aggregates silently fail.

Choosing isolation is a tradeoff: SERIALIZABLE prevents anomalies but tanks throughput; READ COMMITTED is fast but unsafe for concurrent modification of the same row. The solution is usually either (a) use SERIALIZABLE or REPEATABLE READ when you modify shared state, (b) lock rows explicitly with SELECT FOR UPDATE, or (c) redesign to avoid concurrent writes to the same row.

## Practice

**Problem:** Two concurrent data quality jobs both run a daily refresh of `job_postings_fact`. Both jobs:
1. Count the current number of work-from-home jobs.
2. Insert a new audit record with that count plus 1 (simulating an aggregation).
3. Update a shared statistics table.

Without isolation control, the second job's read might see the first job's count, both increment it, but the second write overwrites the first—losing one increment. Write a solution that prevents lost updates.

```sql
-- Solution: Use explicit row-level locking with SELECT FOR UPDATE
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- Lock the statistics row to prevent concurrent modification
SELECT * FROM job_statistics 
WHERE stat_id = 1 
FOR UPDATE;

-- Now read the current count safely
SELECT COUNT(*) AS current_wfh_count 
INTO @wfh_count
FROM job_postings_fact 
WHERE job_work_from_home = true;

-- Insert audit record
INSERT INTO job_audit_log (logged_at, wfh_count, job_name)
VALUES (NOW(), @wfh_count + 1, 'daily_refresh');

-- Update shared state with the lock held
UPDATE job_statistics 
SET last_wfh_count = @wfh_count + 1, last_updated = NOW()
WHERE stat_id = 1;

COMMIT;
```

## Notes

- **Autocommit is the enemy:** Most SQL IDEs/clients default to autocommit. Turn it off explicitly when testing concurrent behavior, or wrap operations in `BEGIN...COMMIT`.
- **SELECT FOR UPDATE is row-level, not global:** It locks only the rows matched by the query. If two transactions lock different rows, they don't block each other—be precise about what you're protecting.
- **SERIALIZABLE is slower but safest:** For critical ETL steps, use `ISOLATION LEVEL SERIALIZABLE`, especially in financial or compliance contexts. Accept the performance hit.
- **Phantom reads are the forgotten cousin:** Even REPEATABLE READ allows phantoms (new rows inserted between your reads). If you rely on counting or range predicates across concurrent inserts, you need SERIALIZABLE.
- **Reconnect isolation concepts to query optimization:** Isolation and locking interact with table locks, index behavior, and deadlock graphs—worth revisiting in the context of EXPLAIN ANALYZE on high-concurrency workloads.
