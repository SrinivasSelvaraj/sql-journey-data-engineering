---
date: 2026-10-22
phase: sql
topic: Query plan analysis: understanding EXPLAIN output
---

# Query plan analysis: understanding EXPLAIN output

*SQL for analytics and engineering*

## Concept

EXPLAIN output reveals the execution plan a database optimizer chooses for your query, showing which tables are scanned, what indexes are used, join strategies, and estimated row counts. Understanding this is critical because a syntactically correct query can be catastrophically slow—sequential scans on large tables, nested loop joins on unindexed columns, or redundant sorting can mask themselves behind correct results. When you can read EXPLAIN, you stop guessing and start diagnosing: you see whether a missing index is the bottleneck, whether the optimizer is choosing a full table scan when an index exists, or whether your join condition is forcing a hash join instead of using a btree index.

In interview conditions especially, explaining your reasoning about query performance matters as much as the query itself. An interviewer may ask you to predict performance or optimize a slow query—EXPLAIN lets you prove your assumptions rather than making them. The output typically shows node type (Seq Scan, Index Scan, Hash Join, Merge Join), estimated cost, estimated rows, and actual rows (if you run EXPLAIN ANALYZE). A large gap between estimated and actual rows signals a stale statistics problem or a cardinality estimation failure, and that diagnosis is what separates competent engineers from ones who just add indexes randomly.

## Practice

**Problem:** You're investigating why a report filtering job postings by location and salary is slow. Write a query to find job titles with average salary over $100k, posted in the last 6 months, remote-eligible—and then write the EXPLAIN to diagnose it.

```sql
-- The query
EXPLAIN ANALYZE
SELECT 
  job_title_short,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND salary_year_avg > 100000
  AND job_posted_date >= CURRENT_DATE - INTERVAL '6 months'
GROUP BY job_title_short
HAVING AVG(salary_year_avg) > 100000
ORDER BY avg_salary DESC;

-- Expected EXPLAIN output structure (PostgreSQL):
-- Aggregate (cost=X..Y rows=Z)
--   -> Sort (cost=A..B rows=C)
--     -> Seq Scan on job_postings_fact (cost=D..E rows=F)
--           Filter: (job_work_from_home AND salary_year_avg > 100000 AND job_posted_date >= ...)

-- If you see Seq Scan with high cost and the table is large (>1M rows):
-- Create an index on (job_work_from_home, job_posted_date) to enable Index Scan
CREATE INDEX idx_remote_posted ON job_postings_fact(job_work_from_home, job_posted_date);

-- Re-run EXPLAIN ANALYZE to confirm it now uses Index Scan
```

## Notes

- **Seq Scan vs. Index Scan**: A sequential scan is not always wrong—if you're fetching >5–10% of a table, the optimizer may correctly choose Seq Scan over index hopping. The problem is when it chooses Seq Scan *despite* indexes existing because statistics are stale (run `ANALYZE` to refresh) or the index doesn't match your filter columns.

- **Cardinality estimation failure**: EXPLAIN ANALYZE shows "rows=10000 actual 1000000"—this means the optimizer underestimated. Happens with complex predicates or missing statistics. Fix by running ANALYZE, creating multi-column statistics (`CREATE STATISTICS`), or rewriting the query to be more index-friendly.

- **Join order and strategy**: Watch for Hash Join vs. Nested Loop. Hash Join is faster for large tables, but requires enough memory; Nested Loop is slower but safe. If you see an unexpectedly expensive join, check if both tables are filtered aggressively *before* the join.

- **Cost units are relative, not absolute time**: Cost of 1000 doesn't mean 1000ms; it's a dimensionless estimate for comparison. Two plans costing 500 and 5000 means the first is ~10× faster under ideal conditions, but actual time depends on I/O, CPU, memory.

- **Adjacent: index design, query rewriting, and statistics management**: EXPLAIN output drives index creation decisions, informs whether you should break a query into stages, and exposes when to use materialized views or pre-aggregated tables instead of live aggregation.
