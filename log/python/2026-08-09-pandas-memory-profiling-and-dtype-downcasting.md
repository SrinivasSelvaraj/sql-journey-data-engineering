---
date: 2026-08-09
phase: python
topic: pandas: memory profiling and dtype downcasting
---

# pandas: memory profiling and dtype downcasting

*Python for data engineering*

## Concept

Memory profiling identifies which columns consume the most RAM in a DataFrame, while dtype downcasting reduces that footprint by using smaller data types (e.g., `int64` → `int32`, `float64` → `float32`). In data pipelines processing millions of rows, a DataFrame can easily consume gigabytes; downcasting can reduce this by 30–50% without losing precision for most use cases. This matters when working with cloud compute where memory = cost, or when a dataset barely fits in RAM and you need headroom for transformations. Without profiling, you may downcast the wrong columns or miss opportunities to compress; without downcasting, you risk OOM errors on modest hardware or pay unnecessary cloud bills.

The key trade-off is precision: `float32` loses ~7 decimal places of accuracy compared to `float64`, and `int32` maxes out at ~2.1 billion. For salary data, locations, and dates, downcasting is usually safe; for high-precision financial calculations or IDs, it can corrupt data silently. Profiling first—using `memory_usage(deep=True)` and `info()`—lets you make informed decisions about which columns to shrink.

## Practice

**Problem:** A job postings DataFrame has 5M rows and occupies 3.2 GB in memory. The `salary_year_avg` column is currently `float64`, but salaries in the dataset range from $20k to $500k. Downcast it to reduce memory, then verify precision is acceptable for a salary range histogram.

```python
import pandas as pd
import numpy as np

# Profile memory before
df = pd.read_csv('job_postings.csv')
print(df.memory_usage(deep=True))
print(f"Initial memory: {df.memory_usage(deep=True).sum() / 1024**2:.1f} MB")

# Downcast salary column
df['salary_year_avg'] = pd.to_numeric(df['salary_year_avg'], downcast='integer')
# Or manually: df['salary_year_avg'] = df['salary_year_avg'].astype('int32')

# Downcast boolean and other columns
df['job_work_from_home'] = df['job_work_from_home'].astype('bool')
df['job_id'] = df['job_id'].astype('int32')  # assuming IDs < 2B

# Profile memory after
print(f"Final memory: {df.memory_usage(deep=True).sum() / 1024**2:.1f} MB")

# Verify salary precision (should be exact for annual salaries in dollars)
print(df['salary_year_avg'].describe())
```

## Notes

- **Profile before downcast:** Always run `memory_usage(deep=True)` and `df.info()` first; targeting the wrong columns wastes effort.
- **Integer vs. float downcasting:** Use `pd.to_numeric(..., downcast='integer')` for automatic safe downcasting; salaries as integers (in dollars) avoid floating-point artifacts.
- **Strings and categories:** Object columns (strings) often consume 2–3× their size; consider `pd.Categorical` for repetitive values like job titles or locations.
- **Type hints + downcasting:** In production pipelines, combine downcasting with type hints (`salary: int32`) to catch dtype mismatches early and document intent.
- **Connects to:** Parquet compression, chunked reading, lazy evaluation (Polars/DuckDB), and cost modeling in cloud environments.
