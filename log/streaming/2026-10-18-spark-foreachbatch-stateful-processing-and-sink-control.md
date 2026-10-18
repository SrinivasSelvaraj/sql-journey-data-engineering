---
date: 2026-10-18
phase: streaming
topic: Spark foreachBatch: stateful processing and sink control
---

# Spark foreachBatch: stateful processing and sink control

*Streaming and distributed processing*

## Concept

`foreachBatch` is a Spark Structured Streaming API that lets you run arbitrary code on each micro-batch as a DataFrame, giving you fine-grained control over what happens after transformation but before the sink. Unlike `foreach` (which operates row-by-row), `foreachBatch` receives the entire batch as a DataFrame, letting you reuse standard Spark DataFrame operations and write to multiple sinks or perform stateful logic.

This matters because streaming sinks often have constraints: some don't support exactly-once semantics natively, some require custom deduplication logic, and some demand that you maintain state across batches (like idempotency keys, watermarks, or aggregation windows). Without `foreachBatch`, you're locked into the limited sink options and cannot easily implement stateful deduplication or conditional multi-sink writes.

Without it, you either write to a single sink with limited guarantees, or you lose the ability to inspect and act on the batch as a coherent unit. This breaks use cases like "write new records to Iceberg but only if they don't already exist" or "route failed validation rows to a quarantine table while good rows go to the warehouse."

## Practice

**Problem:** Stream job postings into a data lake. Deduplicate by `job_id` using a state table, then write clean records to Iceberg and failed validations to a quarantine table.

```sql
-- Not purely SQL, but the foreachBatch pattern in PySpark:
query = (df_stream
  .filter(col("salary_year_avg") > 0)  # basic validation
  .writeStream
  .foreachBatch(
    lambda batch_df, batch_id: 
      # Deduplication: left anti-join against state
      batch_df
        .join(
          spark.read.table("job_postings_state"),
          on="job_id",
          how="left_anti"
        )
        .write
        .format("iceberg")
        .mode("append")
        .saveAsTable("job_postings_fact"),
      # Capture failed rows separately
      batch_df
        .filter(col("salary_year_avg") <= 0)
        .write
        .format("iceberg")
        .mode("append")
        .saveAsTable("job_postings_quarantine")
  )
  .option("checkpointLocation", "/path/to/checkpoint")
  .start()
)
```

## Notes

- **State table must be idempotent:** if your batch retries, the state table should already contain the dedup key, or use MERGE (update-or-insert) to avoid duplicates.
- **Checkpoint location is mandatory:** `foreachBatch` still requires a checkpoint directory to track which batches have been processed; forgetting this causes reprocessing on failure.
- **Connects to:** idempotent writes, watermarking, complex join logic in streaming, multi-sink architectures, and the trade-off between micro-batch and continuous modes (foreachBatch only works with micro-batch).
- **Common mistake:** mutating external state (e.g., incrementing a counter) inside `foreachBatch` without considering that batches may be retried; always treat the batch as an atomic unit.
- **Revisit:** the difference between `outputMode` (Append, Update, Complete) and how each interacts with stateful operations; `foreachBatch` gives you escape hatch control but responsibility for semantics.
