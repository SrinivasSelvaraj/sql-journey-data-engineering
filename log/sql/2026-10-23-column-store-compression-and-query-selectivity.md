---
date: 2026-10-23
phase: sql
topic: Column store compression and query selectivity
---

# Column store compression and query selectivity

*SQL for analytics and engineering*

## Concept

Column stores (like Parquet, ORC, or columnar databases) compress each column independently, enabling massive compression ratios when columns have repeated or similar values. A salary column of mostly $100k–$150k compresses far better than a row store where diverse columns are interleaved. Query selectivity—the fraction of rows a filter removes—directly multiplies compression benefit: filtering to 1% of rows means decompressing only 1% of data in a well-indexed column store.

Without understanding this pairing, you write queries that ignore predicates or filter late, forcing the engine to decompress entire columns. A query selecting three columns from a 10-billion-row table but filtering on a fourth column should push that filter down before projection; otherwise, you decompress and shuffle gigabytes unnecessarily. Modern engines (Spark, DuckDB, Presto) use predicate pushdown to avoid this, but sloppy SQL (subqueries without WHERE, SELECT * before filtering) can prevent the optimizer from doing its job.

The win is dramatic: a selective filter on a well-compressed column can reduce I/O from GB to MB. This is why analytics engineers obsess over partition pruning, clustering keys, and filter placement—it's not pedantry, it's the difference between a sub-second query and a timeout.

## Practice

**Problem:** Given `job_postings_fact`, write a query to find the average salary for remote data analyst roles posted in the last 90 days. Assume the table is stored in Parquet with date and job title as clustering columns. Explain how selectivity helps execution.

```sql
SELECT
  AVG(salary_year_avg) AS avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY
  AND job_work_from_home = TRUE
  AND job_title_short = 'Data Analyst'
  AND salary_year_avg IS NOT NULL;
```

**Why this works:** The WHERE clause applies three filters before aggregation. `job_posted_date` likely prunes partitions or blocks (90 days is selective); `job_work_from_home` is boolean (highly compressible); `job_title_short` is a clustering key. The engine decompresses only rows matching all three, then computes the mean. Without these predicates pushed down, you'd decompress the entire salary column—millions of rows—just to aggregate a subset.

## Notes

- **Predicate pushdown failure:** Wrapping the table in a subquery with SELECT * or CTEs without early WHERE clauses can prevent the optimizer from pushing filters down to the scan. Always filter at the lowest level.
- **NULL handling and compression:** NULL values compress extremely well in column stores (often a single bit). Always include `IS NOT NULL` if nulls skew results; it improves both correctness and execution speed.
- **Selectivity estimation:** A 1% selectivity filter (removing 99% of rows) is worth more than a 50% filter. Indexes and clustering keys matter most on highly selective columns; don't over-index low-selectivity columns.
- **Adjacent topic—partition pruning:** Partition columns (like date) should always appear in WHERE for maximum benefit; columnar engines skip entire partitions at metadata read time, before decompressing anything.
- **Revisit:** Profile actual execution plans (EXPLAIN) on your target engine to confirm filters are pushed down. Different engines (Snowflake, BigQuery, Spark) have different thresholds and heuristics for pushdown.
