---
date: 2026-10-31
phase: cloud
topic: Data archival and retrieval performance
---

# Data archival and retrieval performance

*Cloud platforms and storage*

## Concept

Data archival moves infrequently accessed data to cheaper storage tiers (cold storage, glacier, tape) to reduce cloud costs while keeping it retrievable. The performance trade-off is intentional: archived data has higher latency on retrieval but lower storage cost per GB. Without a deliberate archival strategy, you pay premium rates for all historical data forever—a job postings table with millions of old records from 2015 still occupies hot storage alongside active 2025 postings.

The critical moment is when your query suddenly becomes expensive. A scan of old archived data may trigger full table reconstruction or egress fees you didn't anticipate. Cloud platforms (S3 Glacier, BigQuery Archive Storage, Snowflake Iceberg) charge differently for storage, scanning, and retrieval. Knowing *where* your data lives—and what happens when you query it—is the difference between a $50 query and a $5,000 surprise.

## Practice

**Problem:** Your job_postings_fact table has grown to 500 GB. Posts from before 2024 are queried rarely, but they're still in hot storage costing $0.023/GB/month. You need to archive Q1–Q3 2023 data and still answer historical salary trend queries without manual restoration delays.

```sql
-- Move old partitions to cold storage (example: BigQuery)
ALTER TABLE job_postings_fact
SET OPTIONS(
  require_partition_filter = true
);

-- Query only recent data (fast, cheap)
SELECT 
  job_title_short,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_posted_date >= '2024-01-01'
GROUP BY job_title_short;

-- Archive old data to cheaper tier (one-time setup)
-- In BigQuery: export Q1-Q3 2023 to GCS Archive Storage, then delete from main table
-- In Snowflake: CREATE ICEBERG TABLE with TIME TRAVEL retention, move old micro-partitions to Iceberg

-- When you *need* 2023 data, restore it explicitly
-- (cost is now explicit; you know what you're paying for)
SELECT job_title_short, COUNT(*) 
FROM archived_job_postings_2023
WHERE job_posted_date BETWEEN '2023-01-01' AND '2023-09-30'
GROUP BY job_title_short;
```

## Notes

- **Partition elimination is your friend:** Use `require_partition_filter = true` to force queries to specify a date range; prevents accidental full-table scans of archived data.
- **Egress fees are real:** Moving data out of cold storage (or cross-region) can cost as much as the storage itself—factor retrieval cost into archival decisions.
- **Time-to-retrieval vs. cost trade-off:** Glacier = weeks, Archive Storage = hours, hot SSD = milliseconds. Choose based on your SLA, not just price.
- **Connect to retention policies:** Archival often pairs with data governance—know your compliance hold periods before deleting "old" data.
- **Test query performance before archiving:** A query that was fast on 10 GB may be slow on a 500 GB archive; benchmark cold-storage retrieval latency early.
