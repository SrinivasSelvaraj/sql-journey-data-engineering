---
date: 2026-09-28
phase: streaming
topic: Deduplication by key and time windows
---

# Deduplication by key and time windows

*Streaming and distributed processing*

## Concept

Deduplication by key and time windows removes duplicate records in streaming systems where the same event arrives multiple times (due to retries, network failures, or replication) within a bounded time interval. In unbounded streams, you cannot deduplicate across all history—you must define a window (e.g., 1 hour, 1 day) and track which keys have been seen within that window, discarding subsequent arrivals of the same key.

This matters because downstream systems and metrics break under duplicates: counts inflate, aggregates become unreliable, and joins produce Cartesian explosions. Without deduplication, a job posting arriving three times due to a failed acknowledgment gets counted as three separate postings, inflating your vacancy metrics.

The hard part is choosing the window size and retention strategy. Too small a window and duplicates arriving just outside it slip through; too large and state memory explodes. Most streaming engines (Spark Structured Streaming, Flink, Kafka Streams) offer stateful deduplication operators that manage this trade-off by tracking keys in a time-bounded state store.

## Practice

**Problem:** You ingest job postings from multiple sources. The same job (identified by `job_id`) may arrive 2–3 times within 10 minutes due to API retries. You need to deduplicate by `job_id` within a 10-minute window, keeping only the first occurrence.

```sql
WITH deduplicated AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    ROW_NUMBER() OVER (
      PARTITION BY job_id 
      ORDER BY job_posted_date ASC
    ) AS rn
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_TIMESTAMP - INTERVAL 10 MINUTE
)
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM deduplicated
WHERE rn = 1;
```

In a true streaming context (Spark Structured Streaming), use `dropDuplicates()` with a watermark:
```sql
SELECT *
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_TIMESTAMP - INTERVAL 10 MINUTE
GROUP BY job_id
HAVING ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY job_posted_date) = 1
```

## Notes

- **Window size choice is domain-specific:** 10 minutes works for APIs with predictable retry budgets; financial transactions may need 24–48 hours. Profile your duplicate arrival patterns first.
- **Statefulness has cost:** Tracking keys in memory or external state stores (Redis, RocksDB) consumes resources. Plan for state cleanup (TTL) to avoid unbounded growth.
- **First vs. latest:** Decide whether to keep the first occurrence (safest for immutable events) or the latest (good for mutable snapshots like job status updates). The example above keeps first.
- **Related to: exactly-once semantics, idempotency keys, and event ordering.** Deduplication is one layer; you also need end-to-end idempotent writes and deterministic ordering within your window.
- **Common mistake:** Applying deduplication *after* aggregation. Deduplicate *before* counting, summing, or joining—the order matters for correctness.
