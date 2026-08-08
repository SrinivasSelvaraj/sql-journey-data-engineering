---
date: 2026-08-08
phase: sql
topic: Reading an EXPLAIN plan
---

# Reading an EXPLAIN plan

*SQL for analytics and engineering*

## Concept

An EXPLAIN plan shows how a database engine *will* (or *did*) execute a query—the order of operations, which indexes are used, estimated row counts, and cost metrics. Reading it reveals bottlenecks: sequential scans on large tables when an index exists, expensive nested loops instead of hash joins, or filters applied *after* joining millions of rows instead of before. Without this skill, you optimize blindly—guessing at query rewrites while missing the actual culprit, or believing a query is fast when it only *feels* fast on small datasets.

The output varies by database (PostgreSQL's EXPLAIN ANALYZE is verbose; BigQuery's @@ SCRIPT results are terse), but the core questions are universal: *Which table is scanned first?* *Is the filter pushed down to the table scan?* *Why are 10M rows flowing through a join when filtering first would reduce it to 10K?* Learning to read these plans trains you to think like the optimizer and catch the difference between a query that's *syntactically correct* and one that's *efficient at scale*.

## Practice

**Problem:** You're asked to find all work-from-home job postings in the past 30 days with salary > $100k, and you need to ensure the query is fast even on a 50M-row table. Write the query and explain what the EXPLAIN plan should show to confirm it's optimized.

```sql
EXPLAIN ANALYZE
SELECT 
  job_id, 
  job_title_short, 
  salary_year_avg, 
  job_posted_date
FROM job_postings_fact
WHERE job_work_from_home = true
  AND salary_year_avg > 100000
  AND job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY job_posted_date DESC;
```

**What to look for in the plan:**
- A sequential scan on `job_postings_fact` is a red flag; you'd want an index on `(job_posted_date, job_work_from_home, salary_year_avg)` or a composite index that lets the planner filter before scanning.
- The **Filter** node should show all three WHERE clauses applied early (not after a join or sort).
- **Rows** (estimated vs. actual) should be close; if actual >> estimated, statistics are stale.
- No full table sort; if there's a sort, check whether an index on `job_posted_date DESC` exists.

## Notes

- **Common mistake:** confusing EXPLAIN (theoretical) with EXPLAIN ANALYZE (actual execution); ANALYZE runs the query and shows real timings—always use it in non-production or dev, never blindly on production queries.
- **Index confusion:** a filter on column X doesn't guarantee an index is used; the planner weighs cost; sometimes a full scan + in-memory filter is cheaper than an index lookup if the result set is large.
- **Cardinality awareness:** poor row estimates (due to stale stats or unusual WHERE clause combinations) cause the planner to pick the wrong join strategy; `ANALYZE TABLE` refreshes statistics.
- **Connects to:** query rewriting (pushing predicates down), join order optimization, and understanding your database's cost model (CPU vs. I/O trade-offs).
- **Revisit:** when a query slows down after data growth—EXPLAIN plans are your first debugging step before refactoring schema or adding indexes.
