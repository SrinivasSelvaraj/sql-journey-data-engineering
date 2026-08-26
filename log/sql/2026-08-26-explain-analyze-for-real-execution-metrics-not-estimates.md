---
date: 2026-08-26
phase: sql
topic: Explain analyze for real execution metrics not estimates
---

# Explain analyze for real execution metrics not estimates

*SQL for analytics and engineering*

## Concept

The `EXPLAIN ANALYZE` command executes a query and returns **actual runtime metrics** alongside the planner's estimates—rows scanned, execution time per node, memory used, and I/O operations. This is essential because the query planner makes educated guesses based on statistics; when estimates diverge wildly from reality (e.g., planner expects 100 rows but scans 1M), it reveals undersized indexes, stale statistics, or cardinality estimation bugs that pure `EXPLAIN` cannot surface.

Without running `ANALYZE`, you operate blind during performance troubleshooting. A query might look efficient in the plan but thrash disk I/O in production, or an index might exist but not be used because the planner underestimated its benefit. In interview and real scenarios, `EXPLAIN ANALYZE` is your instrument to validate assumptions and prove optimization effectiveness—"I see the planner guessed 50 rows here but we actually touched 50,000; that's why the nested loop is killing us."

Timing is everything: run `ANALYZE` on production-like data volumes in non-critical windows, because it executes the full query and locks resources. For heavy writes or long-running queries, use `EXPLAIN (ANALYZE false)` to see estimates only, or sample smaller datasets safely.

## Practice

**Problem:** You're optimizing a query that finds remote data-entry jobs posted in the last 30 days with salary ≥ $80k. The query feels slow. Use `EXPLAIN ANALYZE` to uncover where the planner's estimates diverge from reality, and identify what's causing the performance bottleneck.

```sql
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT job_id, job_title_short, salary_year_avg, job_posted_date
FROM job_postings_fact
WHERE job_work_from_home = true
  AND job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
  AND salary_year_avg >= 80000
ORDER BY salary_year_avg DESC
LIMIT 20;
```

Expected output will show:
- **Rows: 150 planned, 15432 actual** → missing index on `(job_work_from_home, job_posted_date, salary_year_avg)`
- **Buffers: Shared hit=5000, read=450** → heavy sequential scan despite filtering
- **Execution time: 230ms actual vs. 12ms planner estimate** → cardinality estimation is 100x off

Add the index and re-run `EXPLAIN ANALYZE` to confirm improvement.

## Notes

- **Planner vs. Reality Gap:** Estimates assume uniform distribution and outdated statistics. `ANALYZE` immediately exposes when assumptions break (e.g., 80% of rows have `job_work_from_home=true` but planner thinks 10%).
- **Always use `BUFFERS` and `TIMING`:** These flags add I/O and wall-clock timing detail; without them, you miss cache behavior and actual latency contributors.
- **Run on a copy or off-peak:** `EXPLAIN ANALYZE` fully executes the query—lock tables, consume CPU, and potentially interfere with live traffic.
- **Update table statistics:** If estimates are consistently wrong across queries, run `ANALYZE job_postings_fact;` to refresh the planner's histogram of column values.
- **Related: Query plans, index selection, cardinality estimation, and the cost model:** Understanding why the planner chose a strategy is half the battle; `ANALYZE` tells you if that choice was right.
