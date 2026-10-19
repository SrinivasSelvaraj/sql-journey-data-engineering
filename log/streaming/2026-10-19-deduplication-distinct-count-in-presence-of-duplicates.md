---
date: 2026-10-19
phase: streaming
topic: Deduplication: distinct count in presence of duplicates
---

# Deduplication: distinct count in presence of duplicates

*Streaming and distributed processing*

## Concept

Counting distinct values in streaming data is deceptively hard because duplicates arrive unpredictably—often due to late-arriving records, retries, data replication, or out-of-order events. Unlike batch processing, where you scan all data once, streaming requires you to maintain state about what you've already seen, and that state can grow unbounded if not managed carefully. Without deduplication logic, metrics drift: you count the same user_id multiple times, inflate revenue totals, or report inflated audience sizes.

The core challenge is the **state problem**: how long do you remember that you've seen a record? Forever (memory explosion) or with a time window (risk losing late-arriving duplicates)? In distributed systems, this is compounded by idempotency guarantees—you need upstream systems to assign unique identifiers or checksums so downstream consumers can recognize and reject replayed messages. Without this, a single Kafka partition rebalance or Flink checkpoint can cause duplicates to slip through.

## Practice

**Problem:** Count distinct job_ids posted in the last 7 days using a streaming pipeline. Duplicates arrive because job_posting events are replayed on subscription reconnect. You need to emit the count every hour and handle late arrivals up to 24 hours.

```sql
-- Streaming deduplication + distinct count (Flink SQL / Kafka)
CREATE TABLE job_postings_dedup AS
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  ROW_NUMBER() OVER (
    PARTITION BY job_id 
    ORDER BY job_posted_date DESC
  ) AS rn
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7' DAY;

-- Count distinct, windowed by hour
SELECT 
  TUMBLE_START(job_posted_date, INTERVAL '1' HOUR) AS hour_bucket,
  COUNT(DISTINCT job_id) AS distinct_jobs_posted
FROM job_postings_dedup
WHERE rn = 1  -- Keep only first occurrence per job_id
GROUP BY TUMBLE(job_posted_date, INTERVAL '1' HOUR);
```

## Notes

- **State retention vs. memory**: Set your deduplication window explicitly (24 hours here). Longer windows catch more late arrivals but consume more state; shorter windows fail silently on late data.
- **Idempotency key design**: Duplicates must be deterministic—use (job_id, job_posted_date) as composite key or add a hash of the full record. Avoid timestamps from the processing system; use event time.
- **Late arrival handling**: `ALLOWED_LATENESS` in Flink or watermarking strategies prevent dropping real late data while still managing state. Balance this against your SLA.
- **HyperLogLog vs. exact distinct**: If your dataset is huge and approximate counts suffice, HyperLogLog uses O(log N) space instead of O(N). Trade accuracy for scalability.
- **Adjacent topics**: Idempotent writes (at-least-once + dedup = exactly-once), watermarking strategies, state backends (RocksDB), and slowly-changing dimension (SCD) handling all intersect here.
