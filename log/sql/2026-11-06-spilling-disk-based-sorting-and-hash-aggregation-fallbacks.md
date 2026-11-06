---
date: 2026-11-06
phase: sql
topic: Spilling: disk-based sorting and hash aggregation fallbacks
---

# Spilling: disk-based sorting and hash aggregation fallbacks

*SQL for analytics and engineering*

## Concept

Spilling occurs when an in-memory operation (sorting or hash aggregation) exceeds available RAM and the query engine writes intermediate results to disk. Without spilling, a query simply fails with an out-of-memory error; with it, execution slows dramatically but completes. This is critical in analytics because a single poorly-written aggregation or sort over millions of rows can consume gigabytes of memory—especially in shared environments where memory per query is capped.

Hash aggregation is the primary culprit. When you `GROUP BY` on a high-cardinality column (e.g., user_id across 10M records), the engine builds an in-memory hash table with one entry per distinct group. If that table grows beyond the memory budget, it spills to disk, forcing expensive I/O for every new group inserted. Similarly, sorting large result sets without a useful index forces a full sort in memory; if the dataset exceeds memory, the engine partitions it, sorts chunks on disk, and merges them back.

In interviews and production, recognizing spill risk means: (1) understanding cardinality of your `GROUP BY` columns, (2) knowing your system's memory limits per query, (3) pushing filters down to reduce input size, and (4) rewriting queries to avoid unnecessary high-cardinality operations. A query that spills is one step away from timeout or failure under load.

## Practice

**Problem:** You need to report average salary by job title and location, but the raw table has 2M rows. A naive `GROUP BY job_title_short, job_location` risks high cardinality (thousands of distinct combinations). Write a query that minimizes spill risk while still answering the question accurately.

```sql
-- Risky: if job_title_short × job_location has 50k+ distinct combos,
-- the hash table for GROUP BY will spill
SELECT 
  job_title_short,
  job_location,
  COUNT(*) as count_postings,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY job_title_short, job_location
ORDER BY count_postings DESC
LIMIT 100;

-- Better: pre-filter and aggregate at lower cardinality
WITH filtered AS (
  SELECT 
    job_title_short,
    job_location,
    salary_year_avg
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
    AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
    AND job_location IN (
      SELECT job_location
      FROM job_postings_fact
      GROUP BY job_location
      HAVING COUNT(*) > 100
    )
)
SELECT 
  job_title_short,
  job_location,
  COUNT(*) as count_postings,
  AVG(salary_year_avg) as avg_salary
FROM filtered
GROUP BY job_title_short, job_location
ORDER BY count_postings DESC
LIMIT 100;
```

The second version reduces input rows before aggregation, lowering the cardinality of the hash table and avoiding spill.

## Notes

- **Cardinality estimation is your radar:** Before writing `GROUP BY`, mentally count distinct values. If you're grouping by email or user_id over millions of rows, you will spill; consider bucketing (e.g., by day, region) instead.

- **Filtering before aggregation is the cheapest optimization.** A `WHERE` clause on indexed columns reduces input size drastically, shrinking the hash table and often eliminating spill entirely.

- **Spilling ↔ Query plan observability:** Always read `EXPLAIN` output. Look for "Hash Aggregate" or "Sort" nodes with high memory estimates; if they exceed available memory, you've found your spill risk.

- **Window functions also spill.** `ROW_NUMBER() OVER (PARTITION BY high_cardinality_col)` can spill just like `GROUP BY`. Prefer row-numbering on lower-cardinality columns or pre-aggregate.

- **Related to materialization and temp tables:** Sometimes breaking a spill-prone query into two steps—materialize an intermediate table (smaller cardinality), then aggregate—is faster than accepting spill. Trade disk I/O during spill against explicit I/O of intermediate storage.
