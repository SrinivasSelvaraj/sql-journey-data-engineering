---
date: 2026-10-07
phase: python
topic: Compression libraries: gzip, zstd, parquet codec selection
---

# Compression libraries: gzip, zstd, parquet codec selection

*Python for data engineering*

## Concept

Compression reduces storage and I/O costs but trades CPU cycles for bandwidth. **gzip** (deflate algorithm) offers wide compatibility and moderate compression ratios (~70% reduction on structured data); **zstd** (Zstandard) provides faster decompression and better ratios with tunable compression levels. **Parquet codecs** (snappy, gzip, zstd, uncompressed, lz4) are chosen per-column and affect query performance—snappy is fast but weak; gzip is ubiquitous but slow; zstd balances both. Without compression strategy, pipelines bloat storage, slow data lakes, and fail cost SLAs. Selection matters most when: ingesting high-volume append-only data, writing data lakes that multiple teams query, or optimizing for either write speed (snappy) or read speed (zstd).

## Practice

**Problem:** A daily job_postings_fact table grows 50GB/day. Write a Python pipeline that compresses to Parquet with zstd codec, validates schema and row counts survive the round-trip, and handles missing/corrupt input gracefully.

```python
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
from datetime import datetime
from pathlib import Path
from typing import Tuple

def write_compressed_parquet(
    df: pd.DataFrame,
    output_path: str,
    codec: str = "zstd",
    compression_level: int = 3
) -> Tuple[int, int]:
    """
    Write DataFrame to Parquet with compression, return (rows_written, bytes_written).
    Raises ValueError if schema invalid or row count mismatches.
    """
    if df.empty:
        raise ValueError("DataFrame is empty; refusing to write")
    
    schema = pa.schema([
        ("job_id", pa.int64()),
        ("job_title_short", pa.string()),
        ("salary_year_avg", pa.float64()),
        ("job_work_from_home", pa.bool_()),
        ("job_posted_date", pa.date32()),
        ("job_location", pa.string()),
    ])
    
    try:
        table = pa.Table.from_pandas(df, schema=schema, safe=True)
    except pa.ArrowException as e:
        raise ValueError(f"Schema mismatch: {e}")
    
    rows_before = len(table)
    pq.write_table(
        table,
        output_path,
        compression=codec,
        compression_level=compression_level,
        use_dictionary=True
    )
    
    # Validate round-trip
    table_read = pq.read_table(output_path)
    rows_after = len(table_read)
    
    if rows_before != rows_after:
        raise ValueError(
            f"Row count mismatch: wrote {rows_before}, read {rows_after}"
        )
    
    bytes_written = Path(output_path).stat().st_size
    return rows_before, bytes_written


# Usage with error handling
df = pd.read_csv("job_postings.csv", parse_dates=["job_posted_date"])
try:
    rows, bytes_sz = write_compressed_parquet(
        df, 
        f"job_postings_{datetime.now().date()}.parquet"
    )
    print(f"✓ Wrote {rows} rows, {bytes_sz / 1e9:.2f}GB (zstd)")
except (ValueError, FileNotFoundError) as e:
    print(f"✗ Pipeline failed: {e}")
```

## Notes

- **Codec selection is workload-specific:** zstd level 3–4 often outperforms gzip on CPU/ratio trade-off; snappy is only preferred when decompression latency dominates (interactive queries). Profile your actual data before standardizing.
- **Parquet per-column codecs matter:** low-cardinality string columns (job_location) benefit from dictionary + snappy; high-cardinality numeric columns compress better with zstd. PyArrow respects codec hints per-column if you use `column_encoding` parameter.
- **Common mistake: ignoring decompression in benchmarks.** Write speed is fast with snappy, but if 50 downstream jobs decompress daily, zstd's slower decompression can still save aggregate CPU. Measure end-to-end, not just write time.
- **Type safety prevents silent corruption:** `pa.Table.from_pandas(schema=schema, safe=True)` catches date/null mismatches early. Without it, zstd will compress garbage happily.
- **Adjacent: Parquet statistics and pruning.** Compression pairs with row-group min/max metadata; filters on job_posted_date skip entire blocks without decompression. Learn partition pruning alongside codec choice.
