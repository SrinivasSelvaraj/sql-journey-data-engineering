---
date: 2026-09-26
phase: streaming
topic: Idempotent producers and duplicate elimination
---

# Idempotent producers and duplicate elimination

*Streaming and distributed processing*

## Concept

An idempotent producer guarantees that sending the same message multiple times has the same effect as sending it once. In streaming systems, network failures, retries, and clock skew cause duplicate messages to arrive at your consumer. Without idempotency, you risk double-counting metrics, creating duplicate rows, or applying the same state change twice. This is especially critical in Kafka-based architectures where at-least-once delivery is the default guarantee—you must handle duplicates at the application layer.

Duplicate elimination requires a deduplication key (usually a unique business identifier or message ID) and a way to detect or reject repeated values. In stateless systems, you can check against a recent window of seen IDs in a state store or database. In stateful systems (like Flink or Spark Structured Streaming), you maintain a deduplication window in memory or an external store and discard any record whose dedup key has been seen before within that window.

Without idempotent producers and duplicate elimination, streaming pipelines silently corrupt analytics: counts become inflated, slowly changing dimensions get stale duplicates, and fact tables double-record events. The problem is insidious because it often goes unnoticed until a downstream stakeholder spots the anomaly.

## Practice

**Problem:** Job postings are being produced to Kafka by multiple job boards. Network retries cause the same posting to be produced twice within seconds. You need to load these into `job_postings_fact` such that duplicate postings (same `job_id`) within a 10-minute window are rejected, and only the first occurrence is inserted.

```sql
-- Deduplication using window function and ROW_NUMBER
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
      ORDER BY _kafka_timestamp ASC
    ) AS rn
  FROM kafka_raw_job_postings
  WHERE _kafka_timestamp >= CURRENT_TIMESTAMP - INTERVAL 10 MINUTE
)
INSERT INTO job_postings_fact
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

## Notes

- **Dedup key choice matters:** Use a stable, business-meaningful identifier (job_id here), not timestamps or non-deterministic fields, or you'll deduplicate incorrectly.
- **Window size trade-off:** Larger dedup windows catch more duplicates but consume more state; set it based on your retry SLA and infrastructure capacity.
- **Exactly-once is hard:** Idempotent producers + dedup ≈ exactly-once semantics, but you also need transactional writes to your sink to close race conditions.
- **Connects to:** idempotency keys in APIs, event sourcing patterns, Kafka transactions (`enable.idempotence=true`), and bloom filters for large-scale dedup.
- **Revisit:** Test dedup behavior under replay scenarios (reprocessing historical Kafka offsets) and confirm your state store doesn't grow unbounded.
