---
date: 2026-10-25
phase: python
topic: Pickle and serialization for job checkpointing
---

# Pickle and serialization for job checkpointing

*Python for data engineering*

## Concept

Pickle is Python's native serialization format for converting objects to byte streams and back. In data pipelines, it enables **job checkpointing**—saving the state of a long-running transformation so you can resume from that point instead of recomputing from scratch. Without checkpointing, a 10-hour ETL job that fails at hour 9 loses all progress; with it, you restart from the last saved checkpoint in minutes.

The critical use case: intermediate DataFrames, model states, or cursor positions in streaming jobs. Pickle preserves Python objects exactly as they are in memory, including complex types (nested dicts, custom classes, NumPy arrays). This matters because alternatives like CSV or JSON require schema conversion and lose type information, making resumption error-prone.

Where it breaks: pickling is **Python-version and environment-dependent**. A pickle created with Python 3.9 may fail to unpickle in 3.11. Pickle also carries security risk if you unpickle untrusted data (arbitrary code execution). For production pipelines, always validate the pickle's source and consider versioning your checkpoint format.

## Practice

**Problem:** You're running a nightly job that extracts job postings from an API, validates salary data, and loads into a data warehouse. The API has rate limits, so the extraction takes 4 hours. Your transformation logic is still being debugged and crashes after 2 hours of processing 50,000 records. How do you avoid re-fetching the entire dataset on each retry?

```python
import pickle
import pandas as pd
from pathlib import Path

checkpoint_dir = Path("./checkpoints")
checkpoint_dir.mkdir(exist_ok=True)

# Save checkpoint after extraction
df_raw = extract_from_api()  # Returns 50k rows
checkpoint_path = checkpoint_dir / "job_postings_raw.pkl"
with open(checkpoint_path, "wb") as f:
    pickle.dump(df_raw, f)

# On resume, load from checkpoint instead of re-fetching
if checkpoint_path.exists():
    with open(checkpoint_path, "rb") as f:
        df_raw = pickle.load(f)
else:
    df_raw = extract_from_api()

# Continue with transformation
df_validated = validate_salary(df_raw)
df_final = df_validated.assign(
    job_posted_date=pd.to_datetime(df_validated["job_posted_date"]),
    job_work_from_home=df_validated["job_work_from_home"].astype(bool)
)

# Save another checkpoint before load
load_checkpoint = checkpoint_dir / "job_postings_validated.pkl"
with open(load_checkpoint, "wb") as f:
    pickle.dump(df_final, f)

# Load into warehouse
load_to_warehouse(df_final)
```

## Notes

- **Pickle protocol matters**: Use `protocol=pickle.HIGHEST_PROTOCOL` when saving for faster I/O and smaller file size; document which protocol version your pipeline uses.
- **Checkpoint naming and cleanup**: Include timestamps or batch IDs in checkpoint filenames (`job_postings_raw_20240115_142300.pkl`); implement retention logic to avoid disk bloat.
- **Consider alternatives for long-term storage**: Pickle is great for short-lived checkpoints between pipeline steps, but for archival or cross-language compatibility, prefer Parquet (preserves schema) or cloud-native state stores (S3, DynamoDB).
- **Always validate after unpickling**: Even if you created the pickle yourself, disk corruption or version mismatches can silently produce wrong objects; add assertions on shape, dtypes, and key column presence.
- **Connects to**: dependency versioning (requirements-lock.txt), idempotency (make checkpoints immutable), and distributed systems (checkpointing in Spark uses different mechanisms—Parquet or internal RDD caching).
