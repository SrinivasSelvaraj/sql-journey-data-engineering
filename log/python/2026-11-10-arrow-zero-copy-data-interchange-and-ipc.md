---
date: 2026-11-10
phase: python
topic: Arrow: zero-copy data interchange and IPC
---

# Arrow: zero-copy data interchange and IPC

*Python for data engineering*

## Concept

Apache Arrow is a columnar in-memory format and IPC (Inter-Process Communication) protocol that lets you move data between systems—Python, Rust, C++, JavaScript—*without copying or deserializing*. Instead of converting Parquet → Pandas DataFrame → NumPy arrays (three separate memory layouts), Arrow holds data in a standardized columnar layout that every language understands natively. This matters when you're building pipelines where data passes through multiple processes or languages: a Rust data ingester can write Arrow IPC, Python can read it directly into memory, and pass it to C++ without touching the raw bytes.

Zero-copy works because Arrow defines a standard memory layout (offsets, nulls, values all predictable). Without it, every handoff serializes to JSON or CSV, deserializes on the other end, and loses type information—turning a 100 MB dataset into a 500 MB round-trip. In Python, `pyarrow.RecordBatchFileWriter` and `pyarrow.ipc.new_stream()` let you write streaming Arrow IPC, which is much faster and preserves nullability and decimal precision that CSV mangles.

## Practice

**Problem:** You're building a data ingestion pipeline that reads job postings from a Rust service (which outputs Arrow IPC), validates them in Python with Pydantic, and writes validated records to Parquet. The Rust service sends `job_postings_fact` as Arrow record batches over a socket. Write Python code to read, validate, and store it without unnecessary copies.

```python
import pyarrow as pa
import pyarrow.ipc as ipc
import pandas as pd
from pydantic import BaseModel, field_validator
from datetime import date

class JobPostingRecord(BaseModel):
    job_id: int
    job_title_short: str
    salary_year_avg: int
    job_work_from_home: bool
    job_posted_date: date
    job_location: str
    
    @field_validator('salary_year_avg')
    def salary_positive(cls, v):
        if v < 0:
            raise ValueError('salary must be non-negative')
        return v

# Read Arrow IPC stream from socket/file
reader = ipc.open_stream(socket_or_file)
schema = reader.schema
validated_batches = []

for batch in reader:
    # Convert batch to Pandas, validate row-by-row
    df = batch.to_pandas()
    for _, row in df.iterrows():
        try:
            validated = JobPostingRecord(**row.to_dict())
            validated_batches.append(validated)
        except ValueError as e:
            print(f"Skipped row {row['job_id']}: {e}")

# Convert validated records back to Arrow and write Parquet
validated_df = pd.DataFrame([r.model_dump() for r in validated_batches])
table = pa.Table.from_pandas(validated_df)
pa.parquet.write_table(table, 'validated_job_postings.parquet')
```

## Notes

- **Arrow ≠ Parquet**: Arrow is in-memory format and IPC protocol; Parquet is the on-disk columnar format. Arrow is faster for inter-process work, Parquet is better for storage and compression.
- **Null handling**: Arrow's nullable columns preserve three-valued logic (true/false/null) that SQL expects. NumPy and CSV lose this; use `pyarrow.compute` functions to work with nulls safely.
- **Schema mismatch breaks silently**: Always validate incoming Arrow schema against expected schema using `schema.equals()` or `pyarrow.types.is_*()` functions before consuming batches.
- **Batch size matters**: Large batches (>100k rows) reduce overhead but spike memory; small batches (<1k rows) cause thrashing. Profile with `sys.getsizeof()` and adjust batch size in producer code.
- **Related**: Protocol Buffers and MessagePack serve similar roles for RPC; learn Arrow-Parquet integration for analytics pipelines and `pyarrow.dataset` for querying partitioned Parquet at scale.
