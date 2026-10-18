---
date: 2026-10-18
phase: streaming
topic: Kinesis shards: hot shard problem and resharding
---

# Kinesis shards: hot shard problem and resharding

*Streaming and distributed processing*

## Concept

A **hot shard** occurs when one or more shards in a Kinesis stream receive disproportionately high traffic compared to others, causing that shard to hit its throughput limit (1 MB/sec ingest or 1000 records/sec) while other shards remain underutilized. This happens when your partition key has skewed cardinality—for example, all records going to the same geographic region or job category. Without addressing this, you'll experience throttling exceptions, increased latency, and loss of data if retries aren't configured properly.

**Resharding** is the process of adding or removing shards and redistributing records across them by changing your partition key strategy or the shard count itself. Kinesis supports two resharding operations: *split* (one shard becomes two) and *merge* (two shards become one). However, resharding is not automatic and requires manual intervention via the API or monitoring alerts; during the operation, the old shards enter a "closing" state and new shards become active, which can introduce ordering guarantees issues if not handled carefully.

Understanding hot shards matters because data arrival patterns are unpredictable and non-uniform in production. A naive partition key (like job category or location) can concentrate load on one shard while others idle, wasting provisioned capacity and creating a bottleneck that cascades into downstream systems (Lambda, Firehose, analytics).

## Practice

**Problem:** A job posting stream is partitioned by `job_location`, but 40% of all postings come from "New York, NY". This location's shard is throttling while other location shards have spare capacity. How do you redistribute the load?

```sql
-- Original (uneven) partition key: job_location
-- Result: New York shard gets 40% of traffic, hits 1 MB/sec limit

-- Solution: Use a composite partition key with hash salting
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  -- Create partition key: location + hash salt (0–99)
  CONCAT(
    job_location, 
    '#', 
    CAST(ABS(FARM_FINGERPRINT(job_id) % 100) AS STRING)
  ) AS partition_key
FROM job_postings_fact
-- This distributes the New York 40% across 100 virtual partitions,
-- each mapping to different physical shards via round-robin.
-- Alternatively: use job_id alone if IDs are uniformly distributed.
```

## Notes

- **Hot shard detection:** Monitor `IncomingRecords` and `IncomingBytes` CloudWatch metrics per shard; alert when one shard > 2× average. Resharding should be automated via Lambda + CloudWatch triggers in production.
- **Partition key design is critical:** Avoid low-cardinality keys (Boolean, status enum, top-10 categories). Prefer high-cardinality identifiers (user_id, job_id) or salted composites. Test your key distribution in advance with a histogram of real data.
- **Ordering guarantee trade-off:** Within a single shard, records are ordered. Resharding splits that shard, so records from the old shard and new shard no longer have guaranteed order relative to each other. If strict ordering matters, use a sorting step downstream or consolidate in a database.
- **Cost vs. resilience:** More shards = higher cost but lower hot shard risk. Start conservative (1–2 shards), then right-size based on observed throughput and cardinality of your partition key.
- **Related:** DynamoDB hot partitions have the same root cause; Kafka topics use similar logic but allow automatic rebalancing. Firehose buffering can mask transient hot shards, but doesn't solve the underlying skew.
