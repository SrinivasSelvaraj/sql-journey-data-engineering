---
date: 2026-11-10
phase: python
topic: Parquet reading: column selection and predicate pushdown
---

# Parquet reading: column selection and predicate pushdown

*Python for data engineering*

## Concept

Column selection and predicate pushdown are optimizations that reduce I/O and memory when reading Parquet files. Column selection means reading only the columns you need, not the entire table—Parquet's columnar format makes this efficient. Predicate pushdown means filtering rows *before* loading them into memory by pushing filter conditions down to the file read layer, rather than reading everything and filtering in Python.

These optimizations matter when your Parquet files are large (hundreds of MB to GB) or when you're reading only a few columns from tables with dozens of fields. Without them, you waste I/O bandwidth reading unused columns and waste RAM materializing rows that will be discarded. In production pipelines, this can mean 10–100x slower reads and pipeline failures from memory pressure.

The catch: not all filter expressions can be pushed down. Parquet stores metadata (min/max values per column chunk) that enables pushdown for simple comparisons (`date > '2024-01-01'`) but not for complex logic (`CASE WHEN` expressions, Python functions). Understanding what pushdown supports is crucial for writing efficient, predictable pipelines.

## Practice

**Problem:** You have a 5 GB Parquet file with job postings. You need to extract only remote jobs (job_work_from_home = true) posted after 2024-01-01, and only the job_id, job_title_short, and salary columns. Write a query that selects columns and filters rows at read time.

```sql
SELECT 
  job_id, 
  job_title_short, 
  salary_year_avg
FROM read_parquet('job_postings_fact.parquet')
WHERE job_work_from_home = true
  AND job_posted_date > '2024-01-01'
```

In DuckDB (or Polars/PyArrow with filters parameter), this automatically pushes both the column projection and the WHERE predicates to the Parquet reader, scanning only the relevant row groups and never materializing the full table.

## Notes

- **Pushdown works only on simple expressions**: equality, comparison, AND/OR. Complex predicates like `EXTRACT(YEAR FROM job_posted_date) = 2024` may not push down and force a full scan.
- **Row group metadata is key**: Parquet stores min/max stats per column per row group. If a row group's min date is before 2024-01-01 and max is after, that entire group must be scanned; pushdown doesn't guarantee single-row-group reads.
- **Test with `.explain()` or `.profile()`**: Always verify your filter actually pushed down by checking the query plan; assume nothing.
- **Connects to**: partitioned datasets (Hive-style directory partitioning enables partition pruning, a sibling optimization), file format choice (Parquet vs CSV), and query engine design (Velox, DuckDB's execution layer).
- **Revisit**: what happens with NULL values in predicates, and how to structure your Parquet writes to maximize row group pruning (e.g., sort by date columns if you filter by date often).
