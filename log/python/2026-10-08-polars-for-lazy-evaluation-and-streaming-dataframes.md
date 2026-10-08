---
date: 2026-10-08
phase: python
topic: Polars for lazy evaluation and streaming DataFrames
---

# Polars for lazy evaluation and streaming DataFrames

*Python for data engineering*

## Concept

Polars' lazy evaluation defers computation until `.collect()` is called, allowing the optimizer to fuse operations and reduce memory overhead. Unlike eager evaluation (pandas), lazy execution builds a query plan, applies optimizations like predicate pushdown and projection elimination, then executes efficiently. Streaming mode processes data in chunks without loading the entire DataFrame into memory—critical for datasets larger than RAM or when ingesting unbounded sources.

This matters when pipelines handle gigabyte-scale fact tables or real-time feeds. Without lazy evaluation, each operation (filter, select, join) materializes intermediate DataFrames, wasting memory and CPU. Streaming becomes essential in production ETL where you cannot afford to buffer everything; it forces you to think about data flow and partitioning upfront, making pipelines deterministic and testable.

Breaking points: eager operations like `.head()` or `.sample()` trigger early collection and negate optimization; groupby aggregations without proper partitioning blow up memory in streaming mode; and joining large tables requires careful ordering to avoid Cartesian explosions.

## Practice

**Problem:** You have a job_postings_fact table with 2M rows. Filter for remote work, US-based positions posted in the last 30 days, then calculate median salary by job_title_short. The dataset is 800 MB; you want to avoid materializing intermediate results and run this monthly on fresh data.

```python
import polars as pl
from datetime import datetime, timedelta

# Lazy evaluation with streaming
df_lazy = pl.scan_csv("job_postings_fact.csv")

thirty_days_ago = (datetime.now() - timedelta(days=30)).date()

result = (
    df_lazy
    .filter(pl.col("job_work_from_home") == True)
    .filter(pl.col("job_location").str.contains("US"))
    .filter(pl.col("job_posted_date") >= thirty_days_ago)
    .group_by("job_title_short")
    .agg(pl.col("salary_year_avg").median().alias("median_salary"))
    .sort("median_salary", descending=True)
    .collect(streaming=True)  # Execute with streaming, chunk-based processing
)

print(result)
```

Polars optimizes by pushing filters before groupby, avoiding the materialization of 1.8M filtered-out rows.

## Notes

- **Lazy ≠ Streaming**: Lazy evaluation still loads the optimized result into memory; streaming processes in bounded partitions. Use `streaming=True` only when you know memory is the bottleneck.
- **Debugging tip**: Call `.explain()` before `.collect()` to inspect the query plan and verify optimization happened (e.g., "FILTER pushed before GROUP_BY").
- **Type safety**: Use `.cast()` and schema hints at scan time (`schema={"salary_year_avg": pl.Float64}`) to catch misaligned input early, before compute-heavy operations run.
- **Adjacent concepts**: Relates to partition-aware joins, Parquet predicate pushdown, and columnar I/O; understand these to avoid accidentally triggering full table scans.
- **Common trap**: Mixing eager and lazy breaks optimization—`.with_columns()` on an eager frame followed by lazy operations resets the plan. Keep operations lazy until final `.collect()`.
