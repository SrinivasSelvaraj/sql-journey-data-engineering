---
date: 2026-10-15
phase: cloud
topic: S3 Select and Glacier Select: filtering before transfer
---

# S3 Select and Glacier Select: filtering before transfer

*Cloud platforms and storage*

## Concept

S3 Select and Glacier Select allow you to filter, project, and aggregate data *inside* the storage service before transferring it to your compute layer. Instead of retrieving an entire 10 GB JSON file to your EC2 instance and then filtering it, you push a SQL-like query to S3 or Glacier; only the matching rows are streamed back. This dramatically reduces egress costs and transfer time, especially when your dataset is large but your result set is small.

The catch: this only works on objects in columnar formats (Parquet, ORC) or line-delimited JSON/CSV. Row-oriented compression or encrypted objects may not support it. Without it, you pay for every byte transferred out of S3 and wait for full file decompression on your client—a common hidden cost when analysts treat S3 as a dumb file store rather than a query engine.

## Practice

**Problem:** You have 500 million job postings in S3 as a Parquet file (80 GB compressed). You need only remote work positions posted in the last 30 days with salary > $120k. Transferring the entire file costs $0.02/GB in egress and takes 15 minutes. How do you avoid it?

```sql
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_location
FROM s3_object 's3://jobs-bucket/job_postings_fact.parquet'
WHERE 
  job_work_from_home = true
  AND job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
  AND salary_year_avg > 120000;
```

S3 Select parses only the columns and rows you need, returning ~2 GB instead of 80 GB. Cost drops to $0.04 and runtime to under 30 seconds.

## Notes

- **Columnar format requirement:** Parquet/ORC are optimized for this; CSV works but is slower. Gzip-compressed files cannot use Select—decompress first or accept the transfer cost.
- **Partial column projection matters:** Selecting 5 columns from a 50-column table cuts I/O dramatically; `SELECT *` defeats the purpose.
- **Pushdown timing:** The earlier you filter (in storage, not in your application), the better. Move WHERE and LIMIT clauses into the S3 Select query, not post-fetch.
- **Cost vs. compute trade-off:** S3 Select charges per byte scanned (cheaper than egress), not per byte returned. For extremely selective queries (< 1% match), this is a win; for table scans, compute locally.
- **Related:** Partition pruning (Hive/Glue partitions), query result caching (Athena), and columnar storage strategy all feed into the same principle: minimize data movement.
