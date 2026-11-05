---
date: 2026-11-05
phase: sql
topic: Partition pruning and predicate pushdown in columnar engines
---

# Partition pruning and predicate pushdown in columnar engines

*SQL for analytics and engineering*

## Concept

**Partition pruning** is the ability of a query engine to skip entire partitions (chunks of data) without reading them when a filter makes them irrelevant. **Predicate pushdown** is pushing filter conditions down to the storage layer so filtering happens before data is loaded into memory. In columnar engines like Parquet + DuckDB, Snowflake, or BigQuery, these optimizations are critical because they reduce I/O and CPU work dramatically—often by 10–100×.

Without these optimizations, a query filtering on `job_posted_date >= '2024-01-01'` would still read every partition created before January 1st, even if the table is physically partitioned by date. The engine would load all columns and rows, then filter in-memory. With partition pruning and predicate pushdown, the engine consults partition metadata (min/max values per partition), discards unmatched partitions entirely, and never materializes irrelevant data.

This matters most when: tables are large (100GB+), partitioned smartly (by date, region, category), and filters are selective. Most modern engines do this automatically, but writing queries *aware* of partitioning strategy—filtering on partition keys early—ensures the optimization fires.

## Practice

**Problem:** Write a query that efficiently finds all remote job postings with average salary > $120k posted in the last 30 days. Assume `job_postings_fact` is partitioned by `job_posted_date` (daily partitions). Show why naive vs. optimized queries differ in performance.

```sql
-- NAIVE (likely scans many unnecessary partitions)
SELECT job_id, job_title_short, salary_year_avg, job_location
FROM job_postings_fact
WHERE salary_year_avg > 120000
  AND job_work_from_home = TRUE;

-- OPTIMIZED (partition pruning fires immediately)
SELECT job_id, job_title_short, salary_year_avg, job_location
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
  AND job_posted_date < CURRENT_DATE
  AND salary_year_avg > 120000
  AND job_work_from_home = TRUE
ORDER BY salary_year_avg DESC;
```

The optimized query **filters on the partition key first** (`job_posted_date`), enabling the engine to skip 335+ days of data. It then pushes `salary_year_avg` and `job_work_from_home` predicates down to columnar I/O, reading only relevant columns and rows. The naive query has no partition key filter, so it must scan the entire table before filtering.

## Notes

- **Filter on partition keys early and explicitly:** Always include partition-column predicates near the top of your WHERE clause. Avoid expressions like `WHERE YEAR(job_posted_date) = 2024`—use range predicates instead (`job_posted_date >= '2024-01-01'`).
- **Column selection matters:** Only SELECT columns you need. Columnar engines read one column at a time; unnecessary columns increase I/O cost even after pruning.
- **Join order and pushdown:** Predicate pushdown can happen before joins in some engines (early filtering reduces join size). Understand your engine's join strategy and place selective filters before large joins.
- **Partition strategy must align with queries:** If you partition by `job_location` but always filter by `job_posted_date`, partition pruning fails. Design partitions around your most common filter patterns (often time-based).
- **Adjacent topics:** Statistics and cardinality estimation (why the engine chooses to prune), partition elimination in query plans (EXPLAIN output), and clustering/Z-order for secondary sort keys when partition pruning alone isn't enough.
