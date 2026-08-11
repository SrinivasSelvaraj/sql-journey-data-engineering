---
date: 2026-08-11
phase: modelling
topic: Columnar storage: why Parquet beats CSV
---

# Columnar storage: why Parquet beats CSV

*Data modelling and warehousing*

## Concept

Columnar storage (Parquet, ORC) stores data by column instead of by row. CSV writes every field of every record sequentially; Parquet writes all job_ids together, then all job_titles together, then all salaries. This matters because analytics queries almost never touch every column—you often filter on date and aggregate salary, ignoring location and title entirely.

When you query CSV, the storage engine must decompress and scan the entire row, even columns you don't need. With Parquet, only the columns you reference are read from disk. For a 100-column dataset where you use 5 columns, you've just saved 95% of I/O. This difference compounds: cheaper cloud storage costs, faster query times, smaller memory footprint, and feasible compression (identical values are adjacent in memory, not scattered).

Without columnar storage, your warehouse scales poorly. Teams resort to denormalization or pre-aggregation hacks to avoid full-table scans. Schema design breaks because wide tables become expensive to maintain. Columnar design forces you to think in terms of *which columns actually matter*, naturally leading to cleaner, narrower schemas.

## Practice

**Problem:** Your team queries `job_postings_fact` daily to find average salary by job title for remote positions posted in the last 30 days. CSV forces a full scan of 2 million rows and all six columns every run. Switching to Parquet partitioned by `job_posted_date` and grouped by `job_title_short` should eliminate unnecessary I/O.

```sql
-- Write fact table to Parquet partitioned by date, clustered by title
CREATE TABLE job_postings_fact_pq
USING PARQUET
PARTITIONED BY (job_posted_date)
CLUSTERED BY (job_title_short) INTO 10 BUCKETS
AS
SELECT 
  job_id, 
  job_title_short, 
  salary_year_avg, 
  job_work_from_home, 
  job_posted_date, 
  job_location
FROM job_postings_csv;

-- Query now only reads relevant date partitions and salary + title columns
SELECT 
  job_title_short, 
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact_pq
WHERE job_posted_date >= CURRENT_DATE - 30
  AND job_work_from_home = TRUE
GROUP BY job_title_short;
```

## Notes

- **Compression wins**: Columnar formats compress 10–100× better because repeated values (e.g. "Data Analyst" appears thousands of times) sit adjacent. CSV compression is weak because row data is heterogeneous.
- **Partitioning is not compression**: Partitioning by date is a complementary strategy—it lets the query engine skip entire folders, not columns. Use both.
- **Schema design consequence**: Columnar storage incentivizes narrow, fact-focused tables. Resist the urge to add "just one more field for convenience"—each column has a storage cost, even if unused.
- **Parquet metadata**: Parquet stores min/max and null counts per column chunk. Queries can prune data before scanning. CSV has no metadata.
- **Revisit: projection pushdown, predicate pushdown**: These optimizations are only effective with columnar formats. Understanding them deepens your grasp of query performance.
