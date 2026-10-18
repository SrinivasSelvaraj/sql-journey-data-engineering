---
date: 2026-10-18
phase: streaming
topic: Pub/Sub ordering keys: per-key ordering guarantees
---

# Pub/Sub ordering keys: per-key ordering guarantees

*Streaming and distributed processing*

## Concept

Pub/Sub ordering keys ensure that messages with the same key are delivered to subscribers in the order they were published, while messages with different keys can arrive out of order. This is critical in streaming systems where event sequence matters—for example, a user's account creation must process before a purchase, or a job posting update must reflect before a salary correction. Without ordering keys, the same logical entity's events can be reordered in flight, causing state inconsistency downstream (a refund processed before a payment, a job deletion before its creation).

In distributed systems, global ordering across all messages is expensive and unnecessary; per-key ordering is the practical middle ground. You assign a key (like user_id, job_id, or account_id) to each message, and the broker guarantees delivery order only within that key's partition or stream. This allows horizontal scaling—different keys scale across different workers—while preserving causality for events that belong to the same entity.

## Practice

**Problem:** Job postings arrive out of order on a stream. A job might be updated (salary raised, location changed) before its initial creation event reaches the warehouse, corrupting the fact table. Design a solution to guarantee that all events for the same job_id arrive in publish order.

```sql
-- Publisher: include ordering_key = job_id
-- Pseudo-code for Pub/Sub message
{
  "ordering_key": "job_id",
  "data": {
    "job_id": 12345,
    "event_type": "created",
    "job_title_short": "Data Engineer",
    "salary_year_avg": 120000,
    "job_posted_date": "2024-01-15"
  }
}

-- Subscriber: process ordered stream into staging, then merge into fact
INSERT INTO job_postings_staging
SELECT
  job_id,
  event_type,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  publish_timestamp
FROM pubsub_stream
ORDER BY job_id, publish_timestamp;

-- Merge in order: creation first, then updates
MERGE INTO job_postings_fact AS target
USING (
  SELECT * FROM job_postings_staging
  ORDER BY job_id, publish_timestamp
) AS source
ON target.job_id = source.job_id
WHEN MATCHED AND source.event_type = 'updated' THEN
  UPDATE SET salary_year_avg = source.salary_year_avg, job_location = source.job_location
WHEN NOT MATCHED AND source.event_type = 'created' THEN
  INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
  VALUES (source.job_id, source.job_title_short, source.salary_year_avg, source.job_work_from_home, source.job_posted_date, source.job_location);
```

## Notes

- **Ordering key must be immutable and stable:** use job_id, not job_title; if the key itself changes, you lose ordering guarantees for that entity across the boundary.
- **Ordering is per-key, not global:** do not assume job_id=1 events finish before job_id=2 events start; parallelism happens across keys, not within them.
- **Hot keys create bottlenecks:** if one key (e.g., a viral job posting) receives 100× more events than others, that key's partition becomes a throughput ceiling; consider sharding or bucketing.
- **Idempotency + ordering together:** ordering alone does not protect against duplicates or retries; combine with idempotent writes (deduplication key) for exactly-once semantics.
- **Adjacent topics:** deduplication windows, dead-letter queues for out-of-order detection, event sourcing patterns, and watermarking in windowed aggregations.
