---
date: 2026-10-20
phase: reliability
topic: Query execution metrics and slow query logs
---

# Query execution metrics and slow query logs

*Quality, reliability and the professional layer*

## Concept

Query execution metrics reveal *how* your database actually runs your code—not how you think it runs. Metrics like execution time, rows scanned, plan costs, and I/O operations expose inefficiencies invisible in the query text itself. A query returning correct results in 2 seconds might scan 50 million rows unnecessarily; another might use a full table scan when an index exists. Slow query logs automatically capture queries exceeding a time threshold, creating a feedback loop: identify bottlenecks, fix root causes, measure improvement.

Without this visibility, you optimize blindly. A pipeline owner must distinguish between "slow because the data grew" (expected scaling), "slow because someone wrote N+1 queries" (architectural), and "slow because the index fragmented" (maintenance). Slow query logs are your early warning system—they surface degradation before it becomes a production incident. They also provide evidence: not hunches, but timestamps and execution plans that justify schema changes, index additions, or query rewrites.

This enters the professional layer because it shifts you from "making it work" to "making it work *reliably and predictably*." You become someone who can answer: "Why did the 3 AM job take 40 minutes instead of 8?" and "What will break if we double the data volume?"

## Practice

**Problem:** Your data team runs a daily job that finds the top 10 highest-paying remote jobs by location. It's been running in 3 seconds, but today it took 47 seconds. You have no idea why. Diagnose and fix using execution metrics.

```sql
-- Enable slow query log (example: MySQL/MariaDB)
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 2;

-- Run the slow query with EXPLAIN to see the execution plan
EXPLAIN ANALYZE
SELECT 
  job_location,
  job_title_short,
  salary_year_avg,
  job_posted_date
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND salary_year_avg IS NOT NULL
ORDER BY salary_year_avg DESC
LIMIT 10;

-- The problem: full table scan (no index on job_work_from_home or salary_year_avg)
-- Solution: create a composite index on the WHERE and ORDER BY columns
CREATE INDEX idx_remote_salary 
ON job_postings_fact(job_work_from_home, salary_year_avg DESC)
INCLUDE (job_title_short, job_location, job_posted_date);

-- Verify improvement
EXPLAIN ANALYZE
SELECT 
  job_location,
  job_title_short,
  salary_year_avg,
  job_posted_date
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND salary_year_avg IS NOT NULL
ORDER BY salary_year_avg DESC
LIMIT 10;
-- Now uses index seek, rows scanned drops from 2.1M to ~50K
```

## Notes

- **Execution plans are assumptions.** EXPLAIN shows the *planner's* prediction; EXPLAIN ANALYZE shows what *actually* happened. Always run ANALYZE on production-like data volumes—cardinality estimates fail on small datasets.

- **Slow query logs need rotation.** Without log file management (truncation, archival), slow logs become multi-gigabyte noise. Set up daily rollover and retention policies, or query the `performance_schema` / `pg_stat_statements` instead.

- **Index tuning is context-dependent.** The index that fixes a 47-second query might bloat write performance. Monitor insert/update/delete times; sometimes denormalization or materialized views are better than more indexes.

- **Connects to:** query plan caching (why the same query suddenly performs differently), cardinality estimation bugs, statistics staleness (outdated `ANALYZE TABLE` or table stats), and alerting systems that page you when query time exceeds SLAs.

- **Revisit:** After fixing a slow query, check if the same pattern exists elsewhere in your codebase. One bad query usually has siblings.
