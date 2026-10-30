---
date: 2026-10-30
phase: cloud
topic: Multipart upload and resumable transfers
---

# Multipart upload and resumable transfers

*Cloud platforms and storage*

## Concept

Multipart upload divides large files into smaller chunks uploaded in parallel, then reassembled server-side. This matters when transferring gigabytes of data to cloud storage (S3, GCS, Azure Blob) because a single network failure anywhere in a 10GB upload restarts the entire transfer. Resumable transfers checkpoint progress, so a failed chunk only requires re-uploading that piece. Without multipart upload, you pay for wasted bandwidth on retries and face timeouts on large datasets; cloud storage bills accumulate fast when 80% of a nightly batch re-uploads because the connection dropped at the 9GB mark.

In data pipelines, multipart upload is invisible when using managed tools (Spark to S3, BigQuery load jobs), but becomes critical when building custom ETL. Python's `boto3` with `Config(multipart_threshold=5MB, max_concurrency=10)` or Go's cloud SDK handle this automatically with sane defaults. Understanding the mechanism reveals why a 50MB CSV uploads instantly but a 5GB Parquet file stalls—chunk size, network conditions, and retry logic interact. Cost-wise: retransmitted data counts toward egress, and failed transfers may leave orphaned multipart uploads consuming storage until garbage collection.

## Practice

**Problem:** You export `job_postings_fact` to S3 as a 3.2GB Parquet file nightly. Uploads fail ~20% of the time midway through, forcing a restart from zero. You need to identify upload cost waste and implement resumable transfer.

```sql
-- Simulate identifying large export candidates and their growth
SELECT 
  DATE_TRUNC(job_posted_date, MONTH) as month,
  COUNT(*) as row_count,
  ROUND(COUNT(*) * 0.000512, 2) as est_size_gb  -- rough estimate: 512 bytes/row
FROM job_postings_fact
WHERE job_posted_date >= '2024-01-01'
GROUP BY month
ORDER BY month DESC;

-- Use this to alert when exports exceed safe single-part threshold (~100MB)
-- Then configure multipart: min chunk 5MB, 8 parallel workers
-- In Python: boto3.client('s3', config=Config(multipart_threshold=5242880, max_concurrency=8))
```

## Notes

- **Orphaned multipart uploads cost money**: failed uploads leave incomplete chunks in S3 until a lifecycle policy expires them (usually 7+ days). Set `AbortIncompleteMultipartUpload` in bucket policy to auto-clean after 1 day.
- **Chunk size trade-off**: small chunks = more API calls and overhead; large chunks = slower to retry on failure. 5–50MB is typical; AWS recommends 100MB for 100GB+ files.
- **Resumable transfers require checksums**: ETL tools log part ETags (MD5 per chunk); without validation, corrupted chunks silently pass. Always hash the final object against source data.
- **Connects to**: query optimization (a slow query that generates a massive temp table triggers multipart), data lineage (track where retries happen), and cost attribution (tag uploads by job name).
- **Revisit when**: scaling batch sizes, migrating between cloud providers (GCS and Azure have different resumable APIs), or if bill spikes without load increase (sign of excessive retries).
