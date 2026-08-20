---
date: 2026-08-20
phase: python
topic: Arrow and zero-copy data interchange
---

# Arrow and zero-copy data interchange

*Python for data engineering*

## Concept

Apache Arrow defines a columnar, language-agnostic memory format that enables zero-copy data interchange between processes and systems. Instead of serializing data to bytes and deserializing on the other side (copying), Arrow lets libraries read data directly from shared memory using the same binary layout. This is critical when moving large datasets between Python, Pandas, DuckDB, Polars, or external services—you eliminate the deserialization bottleneck entirely.

Zero-copy matters most in data pipelines where you repeatedly transform the same dataset or pass it between multiple tools. Without Arrow, each hand-off triggers a full copy: Python→Parquet→DuckDB means two serialization cycles. With Arrow, DuckDB can read your Parquet file or Polars DataFrame using the exact byte layout, no reconstruction needed. This reduces both CPU time and memory pressure.

It breaks when tools don't share the Arrow specification (legacy CSV readers, old database drivers), or when your schema is complex (nested types, variable-length strings)—Arrow handles these, but some libraries force you back to row-oriented formats. Practical failure: passing a large Pandas DataFrame to a non-Arrow-aware library triggers a full copy, negating your pipeline's performance gains.

## Practice

**Problem:** You have a fact table `job_postings_fact` with 5M rows. You're loading it from Parquet, filtering it in DuckDB, and passing results to a Polars transform. Without Arrow, each step copies all columns into its own format. Design a schema and query that keeps data in Arrow format end-to-end.

```sql
-- Create job_postings_fact as Parquet (Arrow-backed)
-- DuckDB reads this zero-copy via Arrow
CREATE TABLE job_postings_fact AS
SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location
FROM read_parquet('s3://data/job_postings_fact.parquet');

-- Query stays in Arrow; result is an Arrow Table, not copied rows
SELECT 
    job_title_short,
    AVG(salary_year_avg) as avg_salary,
    COUNT(*) as posting_count
FROM job_postings_fact
WHERE job_work_from_home = true
  AND job_posted_date >= '2024-01-01'
GROUP BY job_title_short
ORDER BY avg_salary DESC
LIMIT 20;
```

The result can be consumed directly by Polars (`pl.from_arrow(result)`) or exported as Parquet—no intermediate copy.

## Notes

- **Mistake:** Loading Parquet to Pandas then to Polars; Pandas forces Arrow→NumPy→Arrow. Use `pd.read_parquet(..., engine='pyarrow')` and prefer Polars for Arrow-native workflows.
- **Mistake:** Assuming all columns fit your schema; Arrow's type system is stricter than CSV. Validate date formats and nullable columns before writing.
- **Adjacent topic:** PyArrow, Polars, and DuckDB's `result_arrow()` API; also Parquet as the production Arrow serialization format (not CSV).
- **Revisit:** Schema evolution (adding columns without rewriting), partitioned Parquet datasets (Hive-style), and memory-mapped files for truly lazy loading.
- **Real cost:** A 1GB Parquet file loaded via non-Arrow path = 2–3GB RAM spike; Arrow reads ~100MB chunks, freeing memory as it processes.
