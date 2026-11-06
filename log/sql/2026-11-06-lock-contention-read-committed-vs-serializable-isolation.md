---
date: 2026-11-06
phase: sql
topic: Lock contention: read committed vs serializable isolation
---

# Lock contention: read committed vs serializable isolation

*SQL for analytics and engineering*

## Concept

**Lock contention** arises when multiple transactions compete for the same rows or pages, blocking or slowing each other. The isolation level you choose determines which locks are held and for how long. **Read Committed** (the default in most systems) acquires locks only for the duration of each statement, releasing them immediately after—this minimizes contention but allows *non-repeatable reads* and *phantom reads* within a transaction. **Serializable** isolation holds locks for the entire transaction duration and may use predicate locking to prevent phantom reads, drastically reducing concurrency when many transactions touch overlapping data.

In analytics and reporting, you often run long transactions that scan large ranges. Under Serializable isolation, a second concurrent transaction writing to the same table may stall indefinitely. Under Read Committed, you risk reading partially updated data mid-transaction, but writers are unblocked. The tradeoff is crucial: Serializable guarantees correctness but can create bottlenecks in high-concurrency environments; Read Committed is faster but demands careful application logic to handle consistency anomalies (e.g., recalculating totals in a loop).

Without understanding this, you may write a slow analytics query that deadlocks under load, or accidentally read inconsistent snapshots when joining tables in separate statements. The solution is to know your isolation level, understand what anomalies it permits, and design queries to either tolerate them (Read Committed with defensive logic) or minimize lock hold time (batch operations, use window functions instead of loops).

## Practice

**Problem:** You're building a daily job market summary. You need to count active job postings and sum salaries by location, but the raw data is being continuously updated by ingestion pipelines. Under Read Committed isolation, your multi-statement transaction may observe salary updates for some jobs but not others, leading to inconsistent aggregates. Write a solution that either ensures consistency or documents the acceptable anomaly.

```sql
-- Solution: Use a single SELECT with atomic aggregation (Read Committed safe)
-- This executes in one statement, minimizing the window for anomaly
SELECT 
  job_location,
  COUNT(*) as job_count,
  AVG(salary_year_avg) as avg_salary,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) as median_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY job_location
ORDER BY job_count DESC;

-- Alternative: If you need multiple aggregates and Serializable guarantees,
-- use explicit transaction isolation or snapshot isolation (if supported)
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN TRANSACTION;
  SELECT COUNT(*) as total_postings FROM job_postings_fact WHERE job_posted_date = CURRENT_DATE;
  SELECT SUM(salary_year_avg) as total_salary FROM job_postings_fact WHERE job_posted_date = CURRENT_DATE;
COMMIT;
```

## Notes

- **Common mistake:** Running separate queries in a loop to build a report under Read Committed, then discovering mid-stream that new rows were inserted, causing double-counts or missed rows. Use window functions and CTEs to capture all logic in one statement.

- **Lock types matter:** Read Committed uses *row locks* (S and X); Serializable may add *range locks* and *predicate locks*, making you vulnerable to blocking. Know your database's locking granularity (row vs. page vs. table).

- **Deadlock risk:** Serializable + multiple concurrent transactions = higher deadlock probability. Read Committed deadlocks are rarer but still possible if transactions access rows in different order. Always code retry logic and test under realistic concurrency.

- **Snapshot Isolation alternative:** Some databases (PostgreSQL, SQL Server) offer SNAPSHOT or REPEATABLE READ, which avoids phantoms without full Serializable overhead—worth checking if available.

- **Adjacent topics:** Query plan optimization (locks are held longer on slower queries), transaction log sizing (long transactions under Serializable bloat the log), and optimistic concurrency control (version numbers as an application-level alternative to locking).
