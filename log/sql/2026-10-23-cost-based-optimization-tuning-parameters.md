---
date: 2026-10-23
phase: sql
topic: Cost-based optimization tuning parameters
---

# Cost-based optimization tuning parameters

*SQL for analytics and engineering*

## Concept

Cost-based optimization (CBO) uses statistics about table size, column cardinality, and data distribution to estimate query execution cost and choose the lowest-cost plan. The optimizer assigns a numerical cost to competing execution strategies (e.g., nested loop vs. hash join, full table scan vs. index seek) and picks the winner. This matters because a suboptimal plan can turn a sub-second query into a timeout; without accurate statistics or CBO tuning, the optimizer may choose a plan that scans 10M rows when filtering could reduce it to 1K.

What breaks without it: stale statistics lead the optimizer to make bad choices (e.g., assuming a WHERE clause filters 50% of rows when it actually filters 0.1%); missing column statistics prevent the optimizer from estimating selectivity; and implicit type conversions or function wrapping can disable index use. Interview-relevant tuning means understanding EXPLAIN output, recognizing when the optimizer's estimates are wrong, and knowing which levers (ANALYZE, statistics hints, join order hints) to pull.

## Practice

**Problem:** You're asked to optimize a slow query that counts remote job postings by title. The table has 2M rows, but `job_work_from_home` has skewed distribution (90% FALSE, 10% TRUE). The naive query runs in 8 seconds; your goal is to identify why and propose a fix.

```sql
-- Slow query: optimizer may assume uniform distribution
SELECT job_title_short, COUNT(*) as count
FROM job_postings_fact
WHERE job_work_from_home = TRUE
GROUP BY job_title_short
ORDER BY count DESC;

-- Solution: Gather statistics, verify plan, and ensure histogram is accurate
ANALYZE TABLE job_postings_fact COMPUTE STATISTICS FOR COLUMNS job_work_from_home;

-- Check EXPLAIN plan (sample output shows selectivity estimate)
EXPLAIN
SELECT job_title_short, COUNT(*) as count
FROM job_postings_fact
WHERE job_work_from_home = TRUE
GROUP BY job_title_short
ORDER BY count DESC;

-- If index exists on job_work_from_home, verify it's being used
-- If cardinality estimate is way off (e.g., estimated 1M rows, actual 200K),
-- the optimizer may have chosen a full scan instead of index + sort.
-- Recompute statistics or use optimizer hint (database-specific):
-- Spark/Hive: /*+ USE_HASH_AGG */ or /*+ BROADCAST(table) */
-- PostgreSQL: SET constraint_exclusion = partition; (for partitioned tables)
```

## Notes

- **Stale statistics are the #1 culprit:** Always run `ANALYZE` or `GATHER_STATISTICS` after bulk loads or schema changes; many teams forget this and blame the optimizer unfairly.
- **Cardinality mismatch + skewed data = worst case:** If a column is 90/10 split but stats assume 50/50, the optimizer underestimates the cost of filtering and may pick a full scan over an index range scan.
- **EXPLAIN is your diagnostic tool:** Learn to read estimated vs. actual rows; a 100× gap is a red flag that stats are stale or a filter condition is unexpected (e.g., implicit cast).
- **Hints are a last resort:** Use them only after confirming the optimizer's logic is wrong; overuse makes queries brittle and hard to maintain across schema changes.
- **Connects to:** query plan caching (compiled plans become wrong if stats drift), partition pruning (CBO must know partition column stats to eliminate partitions), and join reordering (CBO estimates join selectivity to pick left-to-right order).
