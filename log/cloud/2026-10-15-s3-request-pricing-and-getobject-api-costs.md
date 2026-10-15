---
date: 2026-10-15
phase: cloud
topic: S3: request pricing and GetObject API costs
---

# S3: request pricing and GetObject API costs

*Cloud platforms and storage*

## Concept

S3 request pricing charges per API call, not per GB transferred. Every `GetObject` request costs ~$0.0004 (varies by region), meaning 1 million reads = ~$400 in request costs alone, separate from data transfer fees. This becomes critical when data engineers repeatedly scan the same objects without caching or batching—a single poorly-written job that reads a 1 GB file line-by-line using 1 million individual GetObject calls will cost far more in requests than in storage or bandwidth.

Query slowness often stems from request throttling (S3 limits ~3,500 PUT/COPY/POST/DELETE and 5,500 GET/HEAD requests per second per partition key prefix) rather than data size. If your Athena or Spark job suddenly runs 10x slower, check CloudWatch metrics for `4xx` or `5xx` errors; you may be hitting this ceiling on a hot partition without realizing it.

Without understanding this pricing model, teams accidentally optimize for the wrong metric—they compress data to save storage but ignore that their access pattern generates thousands of redundant requests. The fix usually involves batching reads, using columnar formats with partition pruning, or caching results in memory.

## Practice

**Problem:** A daily analytics job reads `job_postings_fact` to calculate average salary by location. The table has 50 million rows stored as newline-delimited JSON in S3 (unpartitioned). The job filters for a single location (`job_location = 'New York, NY'`) but must scan the entire table because there is no partition. It runs in 2 hours and costs $600/month in S3 requests alone.

**Solution:** Repartition the table by `job_location` and convert to Parquet; query only the relevant partition.

```sql
-- Before: Full table scan, millions of GetObject requests
SELECT job_title_short, AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_location = 'New York, NY'
GROUP BY job_title_short;

-- After: Partition and use columnar format
-- Create partitioned Parquet table
CREATE EXTERNAL TABLE job_postings_fact_partitioned (
  job_id INT,
  job_title_short STRING,
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE
)
PARTITIONED BY (job_location STRING)
STORED AS PARQUET
LOCATION 's3://my-bucket/job_postings_partitioned/';

-- Query now reads only 1 partition
SELECT job_title_short, AVG(salary_year_avg) as avg_salary
FROM job_postings_fact_partitioned
WHERE job_location = 'New York, NY'
GROUP BY job_title_short;
```

## Notes

- **Partition key matters more than file size:** A table split into 100 partitions by location means queries hit only the relevant partitions, reducing GetObject calls by 99%. Poor partitioning negates compression gains.
- **Request throttling is silent until it's not:** S3 will slow your queries dramatically before outright rejecting requests. Monitor `ThrottlingException` in CloudWatch; if present, redesign your prefix structure or increase partition key cardinality.
- **Adjacent topic:** S3 Select and Parquet predicates push filtering to S3, reducing data returned and request overhead—always specify columns and use WHERE in Athena rather than fetching raw data.
- **Common mistake:** Treating S3 like a database. Multiple small reads cost more than one large read; batch operations when possible. Avoid loops that call GetObject repeatedly.
- **Revisit:** S3 lifecycle policies (transition to Intelligent-Tiering or Glacier) interact with request pricing—archiving cold data saves storage but makes retrieval expensive; balance based on access patterns.
