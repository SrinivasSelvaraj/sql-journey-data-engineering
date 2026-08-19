---
date: 2026-08-19
phase: sql
topic: Optimizer statistics: when to ANALYZE and why
---

# Optimizer statistics: when to ANALYZE and why

*SQL for analytics and engineering*

## Concept

Optimizer statistics are metadata about table structure and data distribution (row counts, column cardinality, NULL percentages, value histograms) that the query planner uses to estimate cost and choose execution paths. Without fresh statistics, the planner makes poor assumptions: it might choose a full table scan when an index would be faster, or a nested-loop join instead of a hash join. This is especially dangerous in analytics where tables grow over time and data skew changes.

The `ANALYZE` command collects these statistics by scanning the table and storing summaries in the system catalog. Most modern databases (PostgreSQL, Snowflake, BigQuery) have automatic ANALYZE policies, but manual runs are critical after large data loads, significant DELETE/UPDATE operations, or schema changes. Stale statistics compound with time: a table that was balanced three months ago might now have 90% of its rows in one partition, making old cardinality estimates dangerously wrong.

Without accurate statistics, you see symptoms like unexpectedly slow queries, inconsistent runtimes, and query plans that change after a table refresh. In interview settings, you should recognize when a slow query might be a stats problem (not a missing index) and know how to verify and fix it.

## Practice

**Problem:** A job search service runs this query frequently, but after a weekend bulk load of 2M new rows into `job_postings_fact`, the query slows from 200ms to 8 seconds. The query filters on `job_location` and counts by `job_title_short`. There's a non-unique index on `job_location`. The query plan shows a full table scan instead of using the index. How do you diagnose and fix this?

```sql
-- After bulk load, stats are stale. The planner doesn't know
-- job_location cardinality changed; it underestimates selectivity.

-- 1. Check when stats were last updated (varies by database):
-- PostgreSQL:
SELECT schemaname, tablename, last_vacuum, last_analyze
FROM pg_stat_user_tables
WHERE tablename = 'job_postings_fact';

-- 2. Refresh statistics:
ANALYZE job_postings_fact;

-- 3. (Optional) Analyze specific columns if you have many:
ANALYZE job_postings_fact(job_location, job_title_short);

-- 4. Re-run the problematic query; plan should now use the index:
SELECT job_title_short, COUNT(*) as count
FROM job_postings_fact
WHERE job_location = 'New York, NY'
GROUP BY job_title_short
ORDER BY count DESC;

-- 5. Verify the new plan uses the index:
EXPLAIN SELECT job_title_short, COUNT(*) 
FROM job_postings_fact
WHERE job_location = 'New York, NY'
GROUP BY job_title_short;
```

## Notes

- **Automatic vs. manual:** Most clouds (Snowflake, BigQuery) auto-analyze; PostgreSQL has autovacuum but you may need manual ANALYZE after ETL. Know your database's policy before an interview.
- **ANALYZE vs. VACUUM:** ANALYZE collects stats; VACUUM reclaims dead rows. Both are maintenance, but only ANALYZE affects the planner. Don't confuse them.
- **Sampling trade-off:** Large tables can use `ANALYZE ... SAMPLE` (PostgreSQL) to reduce scan time; useful in production to avoid long locks, but less precise for highly skewed data.
- **Partition-level stats:** In partitioned tables, ensure top-level and partition-level stats are current. A query on one partition may use stale global cardinality and make poor join decisions.
- **Interview signal:** If a query is "mysteriously slow" in a problem, always consider asking "when were stats last updated?" before jumping to index design. Shows you think like a DBA.
