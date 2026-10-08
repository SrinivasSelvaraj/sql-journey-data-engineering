---
date: 2026-10-08
phase: python
topic: Arrow and columnar data representation in memory
---

# Arrow and columnar data representation in memory

*Python for data engineering*

## Concept

Arrow is an in-memory columnar format that stores data by column rather than by row—each column lives contiguously in memory. This matters because columnar layouts enable vectorized operations (SIMD), compress better (similar values cluster together), and let you load only the columns you need. Without columnar representation, row-oriented systems force you to deserialize entire rows even when querying one or two fields, wasting CPU, memory bandwidth, and cache.

In data pipelines, Arrow becomes critical when you're moving large datasets between Python, Pandas, DuckDB, or Parquet files. A typical failure mode: loading a 100GB CSV row-by-row into a Python list consumes 10× the memory and runs 100× slower than reading it into a columnar Arrow table. Arrow also enforces schema and type safety—mismatched types fail early rather than silently corrupting downstream logic.

PyArrow, the Python binding, lets you define schemas, validate on read, and convert to/from Pandas without copies. This is essential for testable, typed pipelines: schemas act as contracts, and Arrow's validation prevents bad input from poisoning your ETL.

## Practice

**Problem:** You're building a pipeline to load job postings, filter for remote roles paying >$80k, and write results to Parquet. You need to ensure type safety and reject malformed dates or missing salary values.

```sql
-- Define the schema and ingest with validation
import pyarrow as pa
import pyarrow.parquet as pq
from datetime import date

schema = pa.schema([
    pa.field('job_id', pa.int64(), nullable=False),
    pa.field('job_title_short', pa.string(), nullable=False),
    pa.field('salary_year_avg', pa.float64(), nullable=True),
    pa.field('job_work_from_home', pa.bool_(), nullable=False),
    pa.field('job_posted_date', pa.date32(), nullable=False),
    pa.field('job_location', pa.string(), nullable=False),
])

# Read CSV with schema enforcement
table = pa.csv.read_csv(
    'job_postings.csv',
    schema=schema,
    invalid_row_handler='skip'  # Drop rows that don't match
)

# Filter: remote AND salary > 80k (columnar operations, no row loops)
filtered = table.filter(
    (pa.compute.equal(table['job_work_from_home'], True)) &
    (pa.compute.greater(table['salary_year_avg'], 80000))
)

# Write to Parquet with compression
pq.write_table(filtered, 'remote_high_pay.parquet', compression='snappy')
```

## Notes

- **Column pruning:** Arrow lets you read only `['job_title_short', 'salary_year_avg']` from Parquet without touching other columns—saves I/O and memory.
- **Type coercion vs. validation:** Arrow can cast (coerce) types on read, but stricter pipelines should reject bad input rather than guess intent; use `invalid_row_handler='error'` in tests.
- **Pandas interop:** `.to_pandas()` is zero-copy for simple types but creates a new object layer; understand when you need Arrow tables vs. DataFrames.
- **Schema as contract:** Define schemas in code (or load from a registry) and validate both input and output; this catches bugs upstream and makes tests deterministic.
- **Adjacent topics:** Parquet compression algorithms, partition pruning, predicate pushdown in DuckDB/Polars, and serialization formats (Protocol Buffers, Avro).
