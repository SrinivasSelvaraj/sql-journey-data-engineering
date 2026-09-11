---
date: 2026-09-11
phase: sql
topic: Adaptive query execution and runtime plan changes
---

# Adaptive query execution and runtime plan changes

*SQL for analytics and engineering*

## Concept

Adaptive query execution (AQE) allows a database engine to collect runtime statistics during query execution and reoptimize the plan mid-flight, rather than committing to a static plan chosen at compile time. This matters most when the optimizer's initial cardinality estimates are wrong—common when filtering on correlated columns, applying multiple predicates, or joining tables with skewed distributions. Without adaptive execution, a suboptimal plan (like a nested-loop join instead of hash join) executes in full, wasting CPU and memory even after the optimizer realizes partway through that a better strategy exists.

Modern engines like Spark SQL, Presto, and some versions of PostgreSQL use AQE to handle unknowns: they might start with a broadcast join, detect that one side is larger than expected, and dynamically fall back to shuffle join. Query plans can also shift sort orders, re-partition data, or swap join algorithms when actual row counts diverge from predictions. Understanding when and how these shifts happen helps you write queries that play well with adaptive optimization—avoiding artificial barriers (like non-pushable filters) and ensuring statistics are fresh.

## Practice

**Problem:** You need to find high-paying remote jobs posted in the last 90 days. The naive filter is `job_work_from_home = true AND salary_year_avg > 100000 AND job_posted_date >= CURRENT_DATE - 90`, but you suspect the salary column is sparse (many NULLs) and remote jobs are rare. Write a query that lets the optimizer (or AQE) reorder filters efficiently and avoid computing expensive joins prematurely.

```sql
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_location
FROM job_postings_fact
WHERE 
  job_posted_date >= CURRENT_DATE - 90
  AND job_work_from_home = true
  AND salary_year_avg IS NOT NULL
  AND salary_year_avg > 100000
ORDER BY salary_year_avg DESC
LIMIT 50;
```

**Why this works:** By explicitly filtering `IS NOT NULL` early, you give the optimizer a clear signal that NULL values are unwanted. By ordering filters from most selective (date range, then boolean) to least, you allow AQE to detect early if the remote filter yields few rows and adjust join strategy before pulling large salary data. The `LIMIT` signals that you only need the top 50, so the engine can consider early termination.

## Notes

- **Cardinality estimation is the root cause:** AQE cannot fix a plan that was theoretically optimal at compile time; it only helps when estimates were wrong. Always check `ANALYZE TABLE` freshness and column statistics.
- **Not all operations are re-optimizable:** Some engines only adapt join order and join type, not filter pushdown or projection pruning. Consult your engine's docs (Spark SQL, Presto, BigQuery all differ).
- **Filter ordering matters, but isn't guaranteed:** Even with AQE, a poorly written WHERE clause (e.g., `f(col) > value` where `f` is a UDF) blocks predicate pushdown. Write filters on raw columns when possible.
- **Connect to: index selection, join hints, and explain plan reading.** AQE is invisible in static EXPLAIN output; use runtime metrics (Spark UI, query profiles) to confirm adaptive choices actually happened.
- **Revisit: partitioning strategy and statistics collection.** If your table is partitioned by date, AQE can prune partitions mid-execution; if stats are stale, AQE may not trigger at all.
