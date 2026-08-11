---
date: 2026-08-11
phase: modelling
topic: Partitioning strategy and partition pruning
---

# Partitioning strategy and partition pruning

*Data modelling and warehousing*

## Concept

Partitioning splits a large table into smaller, physically separate chunks—usually by date, region, or category—so queries scan only relevant data. Partition pruning is the engine that makes this work: your query optimizer automatically excludes partitions that cannot contain matching rows, dramatically reducing I/O and execution time. Without partitioning, a query filtering `job_posted_date >= '2024-01-01'` scans every row in a multi-year table; with date-based partitioning, it skips entire months or years of data.

This matters most when your table grows to hundreds of millions or billions of rows, or when query patterns cluster around specific values (dates, geographies, categories). Poorly chosen partitions—or queries that don't align with partition keys—waste storage and CPU. For example, if you partition `job_postings_fact` by `job_posted_date` but always filter on `job_location`, partition pruning never engages, and you've just added maintenance overhead with no benefit.

## Practice

**Problem:** Your analytics team queries recent job postings daily (last 30 days), but the `job_postings_fact` table contains 5 years of data. Unpartitioned, every query scans billions of rows. Design a partitioned schema and write a query that leverages partition pruning.

```sql
-- Partition by job_posted_date (monthly)
CREATE TABLE job_postings_fact (
  job_id INT,
  job_title_short VARCHAR(50),
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(100)
)
PARTITION BY RANGE (YEAR(job_posted_date), MONTH(job_posted_date));

-- Query that triggers partition pruning
-- Only scans partitions for Jan–Feb 2024
SELECT job_title_short, salary_year_avg, job_location
FROM job_postings_fact
WHERE job_posted_date >= '2024-01-01' 
  AND job_posted_date < '2024-03-01'
  AND job_work_from_home = TRUE;
```

The optimizer recognizes the date filter matches the partition key and prunes all other partitions automatically.

## Notes

- **Partition key must align with filter patterns:** Don't partition by `job_title_short` if you always filter on date. Choose keys your queries actually use.
- **Over-partitioning creates overhead:** Too many small partitions increases metadata management and query planning time. Aim for partitions 100 MB–10 GB each.
- **Partition elimination in WHERE clause only:** Pruning works on columns in the `WHERE` clause; `SELECT` and `JOIN` clauses don't trigger it. Ensure filters are pushed down.
- **Connects to:** clustering (secondary sort order within partitions), indexing (finer-grained row elimination), and incremental loading (new partitions arrive daily, old ones stay static).
- **Revisit when:** your table grows beyond your scan budget, or query latency creeps up despite indexes. Profile slow queries to confirm partition pruning is active.
