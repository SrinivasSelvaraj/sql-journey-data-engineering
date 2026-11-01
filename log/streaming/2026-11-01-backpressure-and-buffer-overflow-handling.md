---
date: 2026-11-01
phase: streaming
topic: Backpressure and buffer overflow handling
---

# Backpressure and buffer overflow handling

*Streaming and distributed processing*

## Concept

Backpressure occurs when a data producer generates records faster than a consumer can process them. Without explicit handling, unprocessed events accumulate in memory buffers until they overflow, causing data loss, system crashes, or cascading failures across the pipeline. In streaming systems, this is critical because data arrival is asynchronous and unbounded—you cannot simply "wait for all data" as you would in batch processing.

Backpressure mechanisms include rate limiting (slowing producers), buffering with capacity limits (rejecting or dropping excess data), and applying feedback signals upstream (pull-based consumption instead of push). Without these, a downstream enrichment service that takes 500ms per record cannot handle a Kafka topic producing 1,000 records/second, and your cluster will eventually run out of memory and fail silently or loudly.

The key insight: streaming systems must degrade gracefully under load. Choose to drop old events, delay new ones, or fail explicitly rather than silently accumulate unbounded memory.

## Practice

**Problem:** Job postings stream in at 50k/hour from an external source, but your enrichment service (adding salary bands and location validation) can only process 5k/hour. The enrichment service writes to a bounded queue of 10k messages. After 12 minutes, the queue is full. How do you handle this without losing data?

```sql
-- Solution: Implement tiered buffering with explicit backpressure feedback

-- 1. Create a staging table with ingestion timestamp and processing status
CREATE TABLE job_postings_buffer (
  buffer_id SERIAL PRIMARY KEY,
  job_id INT,
  job_title_short VARCHAR,
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR,
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  processing_status VARCHAR DEFAULT 'pending', -- pending, processing, enriched, dropped
  buffer_slot INT -- track position in bounded queue
);

-- 2. Implement a bounded queue check before inserting
-- Reject inserts if pending + processing count exceeds threshold (10k)
INSERT INTO job_postings_buffer 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location, buffer_slot)
SELECT 
  incoming.job_id,
  incoming.job_title_short,
  incoming.salary_year_avg,
  incoming.job_work_from_home,
  incoming.job_posted_date,
  incoming.job_location,
  ROW_NUMBER() OVER (ORDER BY incoming.job_posted_date) as buffer_slot
FROM incoming_stream incoming
WHERE (
  SELECT COUNT(*) FROM job_postings_buffer 
  WHERE processing_status IN ('pending', 'processing')
) < 10000  -- Hard backpressure limit
ORDER BY incoming.job_posted_date DESC  -- FIFO with recency bias: drop oldest if full
LIMIT 5000; -- Pull rate-limited to enrichment capacity

-- 3. Process in batches matching enrichment throughput (5k/hour)
UPDATE job_postings_buffer 
SET processing_status = 'enriched'
WHERE buffer_id IN (
  SELECT buffer_id FROM job_postings_buffer 
  WHERE processing_status = 'pending'
  ORDER BY ingested_at ASC
  LIMIT 5000
);

-- 4. Monitor queue health to alert upstream to slow down
SELECT 
  processing_status,
  COUNT(*) as queue_depth,
  MAX(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - ingested_at))) as max_wait_seconds
FROM job_postings_buffer
WHERE processing_status IN ('pending', 'processing')
GROUP BY processing_status;
```

## Notes

- **Confusing buffering with solving the root problem:** Adding larger buffers delays failure but doesn't fix slow consumers. Always profile the bottleneck (I/O, CPU, network) and increase throughput, not queue size.
- **Backpressure strategies trade off latency vs. completeness:** Drop old events (lose historical context), delay new events (increase latency), or fail explicitly (alerting but no progress). Choose based on SLA requirements.
- **Connects to:** flow control in Kafka (replica fetch size, broker throughput), circuit breakers in microservices, and watermarks in Apache Flink for tracking progress in event time.
- **Common mistake:** Implementing backpressure only at one layer. A full database write queue is useless if the upstream Kafka consumer has already buffered 100k records in memory.
- **Revisit:** Dead letter queues (where to send dropped/failed records), monitoring queue depth trends over time, and the difference between reactive backpressure (pull-based) and proactive rate limiting (quota-based).
