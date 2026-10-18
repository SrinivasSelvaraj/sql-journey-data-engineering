---
date: 2026-10-18
phase: streaming
topic: RabbitMQ: message queue vs stream comparison
---

# RabbitMQ: message queue vs stream comparison

*Streaming and distributed processing*

## Concept

RabbitMQ offers two distinct primitives for handling continuous data: **queues** (traditional message passing) and **streams** (log-based append-only buffers). Queues are designed for request–response patterns where messages are consumed once and acknowledged, then removed. Streams, by contrast, retain all messages indefinitely, allowing multiple consumers to replay from any position—critical when you cannot afford to lose the arrival order or when downstream systems need to catch up after failures.

The distinction matters acutely in streaming scenarios where data arrives out-of-order or in bursts. A queue guarantees point-to-point delivery but loses history; a stream guarantees immutable ordering and full replay capability. Without streams, a slow or crashed consumer loses unconsumed messages permanently. Without queues, you waste storage and CPU on messages that have already been fully processed.

In data engineering, this choice determines fault tolerance architecture. If you ingest job postings from multiple sources asynchronously, a stream lets you replay ingestion failures or add new consumers (e.g., a new ML feature pipeline) without re-fetching from source systems. A queue would discard those postings the moment a consumer acknowledges them.

## Practice

**Problem:** You are ingesting job postings in real-time from three job boards. Postings arrive out-of-order by `job_posted_date` and at unpredictable rates. You need to:
1. Guarantee no posting is lost, even if your consumer crashes mid-batch.
2. Allow a second consumer (for analytics) to start reading from 1 hour ago without missing data.
3. Deduplicate on `job_id` within a 24-hour window.

**Solution:** Use a RabbitMQ stream for ingestion, then deduplicate on consumption:

```sql
-- Create a deduplication state table (consumer-side)
CREATE TABLE job_posting_seen (
  job_id INT,
  first_seen_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (job_id)
);

-- Consumer 1: ingest and deduplicate into fact table
INSERT INTO job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT 
  stream_msg.job_id,
  stream_msg.job_title_short,
  stream_msg.salary_year_avg,
  stream_msg.job_work_from_home,
  stream_msg.job_posted_date,
  stream_msg.job_location
FROM rabbitmq_stream_consume('job_postings_stream', offset => '-1h') AS stream_msg
LEFT JOIN job_posting_seen USING (job_id)
WHERE job_posting_seen.job_id IS NULL
  AND stream_msg.job_posted_date >= CURRENT_DATE - INTERVAL '1 day';

-- Update dedup state
INSERT INTO job_posting_seen (job_id) 
SELECT DISTINCT job_id FROM job_postings_fact 
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 day'
ON CONFLICT DO NOTHING;
```

The stream persists all postings; offset `-1h` lets Consumer 2 (analytics) start from 1 hour ago without losing data. Consumer 1 uses an idempotent dedup table to handle retries safely.

## Notes

- **Queue anti-pattern for streaming:** Using a queue for multi-consumer replay scenarios causes data loss—the first consumer's ack removes the message before others can read it.
- **Stream storage cost:** Streams retain all messages by default; set a retention policy (`max-age` or `max-length-bytes`) to prevent unbounded disk growth in production.
- **Offset management:** Always track consumer offsets in your datastore (not just in RabbitMQ) so you survive both consumer and message broker restarts.
- **Out-of-order handling:** Streams preserve *arrival order*, not *timestamp order*. Sort by `job_posted_date` in your SQL layer if temporal order matters for analytics.
- **Replay vs. reprocess:** Streams excel at replay (re-reading old messages) but make true reprocessing (modifying messages in-place) difficult—design your pipeline to be idempotent instead.
