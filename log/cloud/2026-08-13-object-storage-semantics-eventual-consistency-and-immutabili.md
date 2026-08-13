---
date: 2026-08-13
phase: cloud
topic: Object storage semantics: eventual consistency and immutability
---

# Object storage semantics: eventual consistency and immutability

*Cloud platforms and storage*

## Concept

Object storage systems like S3, GCS, and Azure Blob Storage guarantee **eventual consistency**, not immediate consistency. When you write an object, it may not be readable by all clients instantly; reads might return stale or missing data for seconds to minutes. This differs sharply from databases, where writes are immediately visible. Immutability means objects cannot be modified in-place—you must write a new version. Together, these semantics force architectural choices: you cannot safely do read-modify-write cycles on shared objects, and you must design for idempotency and retry logic.

This matters acutely in data pipelines. If a job fails partway through writing a Parquet file to S3, you cannot "patch" it—you overwrite the whole thing. If two jobs write to the same path simultaneously, race conditions create data corruption. Eventual consistency bites hardest when you query immediately after a write: analytics queries might operate on stale data. Without understanding these constraints, you build systems that mysteriously fail under load or lose data silently.

## Practice

**Problem:** A daily ETL job reads `job_postings_fact` from a database, aggregates it, and writes summaries as Parquet files to S3 at `s3://analytics/daily_summary/2024-01-15.parquet`. The job sometimes runs twice due to retry logic. Downstream queries read this file immediately after completion and occasionally see incomplete or duplicate data.

**Solution:**

```sql
-- Use a unique write-once path with a job execution ID
-- Instead of: s3://analytics/daily_summary/2024-01-15.parquet
-- Use: s3://analytics/daily_summary/2024-01-15/run_{uuid}.parquet

-- After successful write, update a manifest file atomically:
-- Write to: s3://analytics/daily_summary/2024-01-15/_SUCCESS.json
-- Contents: {"files": ["run_abc123.parquet"], "timestamp": "...", "row_count": 50000}

-- Downstream queries must read the manifest first:
SELECT job_id, job_title_short, salary_year_avg
FROM read_parquet('s3://analytics/daily_summary/2024-01-15/run_abc123.parquet')
WHERE job_posted_date = '2024-01-15'

-- Or use a Delta Lake transaction log (wraps around eventual consistency):
-- WRITE to parquet + update _delta_log/ atomically via Delta protocol
-- Delta's ACID guarantees abstract away S3 eventual consistency concerns
```

## Notes

- **Write-once-read-many (WORM):** design all S3 writes to use unique paths with execution IDs or UUIDs; never overwrite in-place. Pair with a manifest or state file (`_SUCCESS`) to signal completion.
- **Retry idempotency:** because retries may re-write the same data, ensure downstream deduplication logic (e.g., by `(job_id, run_date)` composite key) or use Delta Lake/Iceberg to handle this for you.
- **Query staleness:** add explicit wait logic (sleep 30–60 seconds) or use a state store (DynamoDB, Redis) to track when writes are truly visible before triggering downstream queries.
- **Connected topics:** object storage pricing (pay-per-request; many small writes are expensive), data format versioning (Parquet schema evolution), and transaction log semantics (Delta, Iceberg, Hudi).
- **Revisit:** eventual consistency becomes critical at scale; single-threaded local testing masks these issues. Test with concurrent writes and delayed reads in staging before production.
