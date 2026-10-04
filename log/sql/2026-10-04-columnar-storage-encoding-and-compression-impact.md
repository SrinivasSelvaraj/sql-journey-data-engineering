---
date: 2026-10-04
phase: sql
topic: Columnar storage: encoding and compression impact
---

# Columnar storage: encoding and compression impact

*SQL for analytics and engineering*

## Concept

Columnar storage (Parquet, ORC) stores data by column rather than by row, enabling compression algorithms to exploit repeated values and data type homogeneity. When you query only a few columns from a wide table, columnar formats read only those columns from disk—not the entire row. Combined with encoding schemes (dictionary encoding for low-cardinality strings, run-length encoding for repeated values, bit-packing for integers), columnar storage can reduce data size by 10–100× compared to uncompressed row storage, directly improving query latency and reducing I/O cost.

This matters most in analytics workloads where queries scan millions of rows but touch only a subset of columns. Without compression and columnar layout, a query selecting job_title_short and salary_year_avg from 10M job postings still reads all other columns (job_location, job_work_from_home, etc.). Query engines (Presto, DuckDB, Spark) push column pruning into their planning phase, but only columnar formats guarantee efficient execution. Row-oriented storage (CSV, uncompressed Parquet) defeats these optimizations entirely.

Understanding encoding/compression also explains query plan behavior: you may see identical SQL run 10× faster on compressed Parquet than CSV, not because of the query itself, but because the engine reads 1/10th the bytes from disk and decompresses on-the-fly using SIMD operations.

## Practice

**Problem:** You have a 50 GB CSV export of job_postings_fact. A daily report aggregates average salary by job_title_short for postings in the last 90 days. The query takes 45 seconds. Explain why converting to Parquet with snappy compression might drop this to 3–5 seconds, and write the query you'd expect to see in the query plan.

```sql
-- Original query (slow on CSV, fast on compressed Parquet)
SELECT 
  job_title_short,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY job_title_short
ORDER BY avg_salary DESC;
```

**Why Parquet wins:**
- CSV reads all 6 columns; Parquet reads only job_title_short, salary_year_avg, job_posted_date (≈3/6 data).
- job_title_short (low-cardinality string) compresses via dictionary encoding to 5–10% original size.
- salary_year_avg (numeric) compresses via delta + bit-packing.
- Engine applies column pruning and predicate pushdown on job_posted_date *before* decompression.
- Result: 50 GB → ~2–5 GB on disk; decompression is faster than I/O savings gained.

## Notes

- **Dictionary encoding pitfall:** high-cardinality columns (unique job_ids) don't compress well; if your WHERE clause filters on a high-cardinality column, you don't gain encoding benefit, only general compression.
- **Compression codec trade-offs:** snappy is fast (I/O-bound workloads), gzip is tighter (storage cost), zstd balances both; choose based on whether you're network-bound or CPU-bound.
- **Predicate pushdown:** engines like Spark and DuckDB apply WHERE filters *during* decompression via column statistics (min/max, bloom filters); CSV cannot do this without reading the whole file.
- **Related: columnar query engines** (DuckDB, Polars, DataFusion) execute directly on compressed Parquet without materialization; row-oriented engines (psql, MySQL) must load into memory first.
- **Revisit:** partition pruning (splitting Parquet by date/region) compounds columnar gains; a query on 90 days of data might skip 275 days of Parquet files entirely via partition elimination.
