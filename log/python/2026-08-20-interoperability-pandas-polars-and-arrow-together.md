---
date: 2026-08-20
phase: python
topic: Interoperability: pandas, Polars and Arrow together
---

# Interoperability: pandas, Polars and Arrow together

*Python for data engineering*

## Concept

Interoperability between pandas, Polars, and Arrow matters because modern Python data pipelines often mix libraries for different strengths: pandas for exploratory work and legacy code, Polars for performance and type safety, and Arrow for efficient serialization and zero-copy sharing. Without deliberate conversion and schema alignment, you hit silent type mismatches (pandas int64 vs Polars Int64), memory bloat from unnecessary copies, and runtime failures when passing data between layers.

The friction emerges at boundaries: when you read Parquet with Arrow, transform with Polars, then join with a pandas DataFrame, each library makes different assumptions about nullability, ordering, and precision. Without explicit schema definition and conversion, a nullable integer column becomes non-nullable mid-pipeline, a date becomes a string, or you allocate 2GB of memory instead of 200MB. This breaks downstream assumptions and makes debugging nearly impossible because the failure happens silently or far from its source.

Interoperability demands that you *name your schema*, convert explicitly at boundaries, and treat data type misalignment as a first-class concern. You write code that expects a specific Arrow schema, validates input against it, and converts to the right library for the next step. This is unglamorous but it's what separates fragile scripts from production pipelines.

## Practice

**Problem:** You have a Parquet file of job postings (written with Polars). You need to read it, filter rows where `salary_year_avg > 100000`, enrich using a pandas DataFrame of location metadata, and write the result back as Parquet with a guaranteed schema.

```python
import pyarrow as pa
import pyarrow.parquet as pq
import polars as pl
import pandas as pd

# Define canonical schema upfront
JOB_POSTINGS_SCHEMA = pa.schema([
    pa.field("job_id", pa.int64(), nullable=False),
    pa.field("job_title_short", pa.string(), nullable=False),
    pa.field("salary_year_avg", pa.int64(), nullable=True),
    pa.field("job_work_from_home", pa.bool_(), nullable=False),
    pa.field("job_posted_date", pa.date32(), nullable=False),
    pa.field("job_location", pa.string(), nullable=False),
])

# Read with Arrow, validate schema, convert to Polars for compute
table = pq.read_table("job_postings.parquet", schema=JOB_POSTINGS_SCHEMA)
df_polars = pl.from_arrow(table)

# Filter and select
filtered = df_polars.filter(pl.col("salary_year_avg") > 100000)

# Convert pandas metadata to Arrow, then to Polars for join
location_meta_pandas = pd.DataFrame({
    "job_location": ["New York", "Remote"],
    "region": ["Northeast", "Virtual"]
})
location_meta_arrow = pa.Table.from_pandas(location_meta_pandas)
location_meta_polars = pl.from_arrow(location_meta_arrow)

# Join in Polars (type-safe, efficient)
result = filtered.join(location_meta_polars, on="job_location", how="left")

# Convert back to Arrow and write with schema enforcement
output_table = result.to_arrow()
assert output_table.schema == JOB_POSTINGS_SCHEMA or output_table.schema.is_compatible(JOB_POSTINGS_SCHEMA)
pq.write_table(output_table, "job_postings_filtered.parquet", schema=JOB_POSTINGS_SCHEMA)
```

## Notes

- **Schema as contract:** Define your schema once using PyArrow, validate all inputs against it, and use `pa.Table.validate(schema=...)` or Polars' schema parameter to fail early rather than silently corrupt data downstream.
- **Nullable vs non-nullable matters:** Polars' `Int64` (nullable) and `int64` (non-nullable) are different; pandas treats NaN inconsistently across dtypes. Pin this in your schema and convert explicitly.
- **Arrow is the interchange layer:** Use `to_arrow()` / `from_arrow()` rather than pandas/CSV when moving between libraries—it preserves types and avoids serialization round-trips.
- **Memory efficiency:** Each library has different internal layouts; unnecessary conversions (pandas → Polars → pandas) double memory. Design pipelines to minimize hops and do the expensive work in Polars or with Arrow compute functions.
- **Related: type hints for DataFrames** (e.g., `def process(df: pl.DataFrame) -> pl.DataFrame:`) and testing with hypothesis or pandera to catch type mismatches before production.
