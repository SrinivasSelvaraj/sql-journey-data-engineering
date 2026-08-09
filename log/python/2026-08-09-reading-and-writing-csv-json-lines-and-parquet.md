---
date: 2026-08-09
phase: python
topic: Reading and writing CSV, JSON Lines and Parquet
---

# Reading and writing CSV, JSON Lines and Parquet

*Python for data engineering*

## Concept

CSV, JSON Lines, and Parquet are the three primary file formats in data pipelines. CSV is human-readable but loses type information; JSON Lines (newline-delimited JSON) preserves structure but is verbose and slow; Parquet is columnar, compressed, and type-safe, making it ideal for analytics workloads. In production, you'll encounter all three: CSVs from business exports, JSON Lines from APIs and logs, and Parquet from data warehouses. The format you choose affects parsing speed, storage size, type safety, and how gracefully your code handles corrupted rows—a single malformed date in a CSV can crash an unguarded pipeline, while Parquet's schema enforcement catches schema violations before they propagate downstream.

Reading and writing these formats correctly means building defensive code: validating headers, handling missing values, enforcing types at the boundary (not inside your transformations), and distinguishing between recoverable errors (skip one bad row) and fatal ones (schema mismatch). Without this rigor, pipelines silently drop columns, coerce types incorrectly, or fail mid-batch after processing 10 million rows.

## Practice

**Problem:** You receive a daily job_postings CSV export that may have missing salary values, inconsistent date formats, and occasional extra whitespace. Write code that reads this safely, validates the schema, and writes clean Parquet output that downstream consumers can trust.

```python
import pandas as pd
from datetime import datetime
from pathlib import Path
from typing import Optional
import pyarrow as pa
import pyarrow.parquet as pq

def read_and_validate_job_postings(csv_path: str) -> pd.DataFrame:
    """Read CSV with strict type enforcement and validation."""
    df = pd.read_csv(
        csv_path,
        dtype={
            'job_id': 'int64',
            'job_title_short': 'str',
            'salary_year_avg': 'float64',
            'job_work_from_home': 'bool',
            'job_location': 'str',
        },
        parse_dates=['job_posted_date'],
        na_values=['', 'NULL', 'N/A'],
        skipinitialspace=True,
        on_bad_lines='skip',  # Skip rows that don't match column count
    )
    
    # Validate required columns exist
    required_cols = {'job_id', 'job_title_short', 'job_work_from_home', 'job_posted_date', 'job_location'}
    missing = required_cols - set(df.columns)
    if missing:
        raise ValueError(f"Missing required columns: {missing}")
    
    # Enforce non-null constraints on keys
    if df['job_id'].isna().any():
        raise ValueError("job_id contains null values")
    
    # Coerce salary to non-negative (recoverable error: fill with 0)
    df['salary_year_avg'] = df['salary_year_avg'].fillna(0)
    df.loc[df['salary_year_avg'] < 0, 'salary_year_avg'] = 0
    
    return df

def write_parquet_with_schema(df: pd.DataFrame, output_path: str) -> None:
    """Write DataFrame to Parquet with explicit schema."""
    schema = pa.schema([
        ('job_id', pa.int64()),
        ('job_title_short', pa.string()),
        ('salary_year_avg', pa.float64()),
        ('job_work_from_home', pa.bool_()),
        ('job_posted_date', pa.date32()),
        ('job_location', pa.string()),
    ])
    
    table = pa.Table.from_pandas(df, schema=schema)
    pq.write_table(table, output_path, compression='snappy')

# Usage
df = read_and_validate_job_postings('job_postings.csv')
write_parquet_with_schema(df, 'job_postings.parquet')
```

## Notes

- **CSV pitfalls:** Encoding mismatches (UTF-8 vs Latin-1), inconsistent delimiters, and silent type coercion—always specify `dtype` and `parse_dates` explicitly rather than relying on inference.
- **JSON Lines handling:** Use `pd.read_json(..., lines=True)` or iterate line-by-line with `json.loads()` to handle partial failures; one malformed JSON object shouldn't break the entire read.
- **Parquet strengths:** Columnar storage compresses well, preserves types, and enables predicate pushdown in query engines—prefer Parquet for large datasets and repeated reads.
- **Schema drift:** When source schemas change (new columns, dropped fields), decide upfront: fail fast or backfill nulls? Document this contract in code comments or a schema registry.
- **Adjacent topics:** Type hints on functions, dataclass validation (pydantic), testing with fixtures (pytest with temporary CSV/Parquet files), and logging each validation failure for observability.
