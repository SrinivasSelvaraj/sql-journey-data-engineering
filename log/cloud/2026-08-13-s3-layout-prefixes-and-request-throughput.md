---
date: 2026-08-13
phase: cloud
topic: S3 layout, prefixes and request throughput
---

# S3 layout, prefixes and request throughput

*Cloud platforms and storage*

## Concept

S3 object prefixes (the path structure before the filename) directly impact request throughput because AWS partitions request rate limits by prefix. Each prefix gets ~3,500 PUT/COPY/POST/DELETE requests per second and ~5,500 GET/HEAD requests per second. If you write all objects under a single prefix like `s3://bucket/data/`, you share that quota across your entire workload. Conversely, distributing writes across many prefixes (e.g., by date, region, or job category) parallelizes throughput and avoids throttling.

Layout matters most when you're doing high-frequency batch loads or concurrent queries. Slow queries often stem from throttled S3 requests, which show up as latency spikes or failed retries—not from compute, but from I/O starvation. Without thoughtful prefix design, adding more workers won't help; you'll just queue requests against the same bottleneck.

## Practice

**Problem:** A data pipeline loads job postings every 10 minutes into S3, then Athena queries them by job_posted_date. Currently all files land in `s3://postings-bucket/data/`, causing throttling during peak ingestion. Design a prefix structure that supports parallel writes and efficient querying.

```sql
-- Bad layout: all in one prefix
-- s3://postings-bucket/data/postings_2024_01_15.parquet
-- This shares 3,500 PUT quota across all parallel loaders

-- Good layout: partition by date and hour (write-friendly)
-- s3://postings-bucket/year=2024/month=01/day=15/hour=14/postings_chunk_001.parquet

-- Athena table definition leveraging partitions
CREATE EXTERNAL TABLE job_postings_fact (
    job_id STRING,
    job_title_short STRING,
    salary_year_avg INT,
    job_work_from_home BOOLEAN,
    job_location STRING
)
PARTITIONED BY (
    year INT,
    month INT,
    day INT,
    hour INT
)
STORED AS PARQUET
LOCATION 's3://postings-bucket/';

-- Query a single day: scans only one prefix hierarchy
SELECT job_title_short, COUNT(*) 
FROM job_postings_fact
WHERE year = 2024 AND month = 1 AND day = 15
GROUP BY job_title_short;
```

## Notes

- **Common mistake:** Deep nesting (e.g., `/year/month/day/hour/minute/`) doesn't help throughput—only breadth at the write tier matters. Partition pruning happens at query time, not storage time.
- **Hotspot pattern:** Sequential IDs or timestamps as prefixes (e.g., `job_id_001/`, `job_id_002/`) create contention if traffic clusters on recent IDs. Use hash-based prefixes like `job_id % 256` for even distribution.
- **Connects to:** Glue partition projection and Athena partition pruning; understanding cost (scan volume) vs. speed (request rate).
- **Monitor:** CloudWatch S3 request metrics per prefix; slow queries → check `UserErrors` and `4xx` response codes, not just data scanned.
- **Revisit:** S3 intelligent-tiering and lifecycle policies depend on prefix structure; poor layout wastes money on unintended archival.
