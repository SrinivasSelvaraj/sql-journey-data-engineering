---
date: 2026-10-12
phase: pipelines
topic: Dagster I/O managers: custom serialization and storage
---

# Dagster I/O managers: custom serialization and storage

*Pipelines and orchestration*

## Concept

An I/O manager in Dagster controls how data moves between ops and assets—where it gets written, how it's serialized, and how it's retrieved. By default, Dagster pickles outputs to local disk, which works for development but breaks in production: pickle is Python-only, fragile across versions, and unsafe for untrusted data. Custom I/O managers let you serialize to JSON, Parquet, or custom formats and persist to S3, databases, or cloud storage, making your pipeline language-agnostic and reproducible.

Without explicit I/O management, you lose observability into what data actually persists, where bottlenecks occur, and why reruns fail. A downstream op might expect CSV but receive pickle; a cloud run might have no local disk access; a teammate using R can't consume your pickled outputs. Custom managers make the data contract explicit: "this asset is Parquet in S3" becomes enforceable, and failures become loud rather than silent.

Dagster's I/O manager pattern separates *computation* from *storage*, letting you swap backends (local → S3 → warehouse) without rewriting op logic. This is critical for building pipelines that fail loudly (serialization errors surface immediately) and rerun safely (idempotent writes, clear provenance).

## Practice

**Problem:** You have `job_postings_fact` flowing through three ops: fetch (from API), enrich (add computed fields), and validate. Currently all outputs are pickled locally. In production, you need outputs as Parquet files in S3, with timestamps and lineage tracked. Reruns must not corrupt existing files.

```sql
-- Not SQL, but the I/O manager pattern:
-- Define a custom S3 Parquet I/O manager

from dagster import IOManager, io_manager, DagsterTypeCheck
from dagster_aws.s3 import S3Resource
import pandas as pd

class S3ParquetIOManager(IOManager):
    def __init__(self, s3: S3Resource, bucket: str, prefix: str):
        self.s3 = s3
        self.bucket = bucket
        self.prefix = prefix

    def handle_output(self, context, obj):
        # obj is the DataFrame output from an op
        key = f"{self.prefix}/{context.op.name}/{context.run_id}.parquet"
        obj.to_parquet(f"s3://{self.bucket}/{key}")
        context.log.info(f"Wrote {context.op.name} to s3://{self.bucket}/{key}")

    def load_input(self, context):
        # Load the most recent output for a given op
        source_op = context.upstream_output.op.name
        s3_path = f"s3://{self.bucket}/{self.prefix}/{source_op}/"
        latest = self.s3.list_objects(Bucket=self.bucket, Prefix=s3_path)
        latest_key = sorted(latest['Contents'])[-1]['Key']
        return pd.read_parquet(f"s3://{self.bucket}/{latest_key}")

@io_manager
def s3_parquet_io_manager(init_context):
    return S3ParquetIOManager(
        s3=S3Resource(),
        bucket="my-data-bucket",
        prefix="job_postings"
    )

# In your job definition:
@job(resource_defs={"io_manager": s3_parquet_io_manager})
def ingest_job():
    validate(enrich(fetch()))
```

## Notes

- **Mistake:** Assuming pickle is safe across environments. It isn't—Python versions, library updates, or air-gapped networks will break deserialization silently until downstream code fails.
- **Mistake:** Hardcoding paths in ops. I/O managers decouple storage from logic; ops should only know *what* they output, not *where*.
- **Adjacent topic:** Dagster's type system pairs naturally with I/O managers—declare `Out(pd.DataFrame)` and let the manager handle serialization for that type.
- **Worth revisiting:** Multi-asset I/O managers let you write multiple tables to one location atomically; essential for maintaining referential integrity in fact tables like `job_postings_fact`.
- **Production gotcha:** Version your Parquet schema and add migration logic to handle schema drift across reruns; otherwise old runs become unloadable.
