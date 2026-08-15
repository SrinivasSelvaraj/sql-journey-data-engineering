---
date: 2026-08-15
phase: streaming
topic: Backpressure and throughput limits
---

# Backpressure and throughput limits

*Streaming and distributed processing*

## Concept

Backpressure is the mechanism that slows down a data producer when a consumer cannot keep up, preventing memory exhaustion and data loss in streaming pipelines. Without it, a fast source flooding a slow sink creates an unbounded queue: messages accumulate in memory, the system crashes, or data is silently dropped. In distributed systems, backpressure propagates upstream—a bottleneck at one stage signals all previous stages to reduce their emission rate.

Throughput limits are the intentional ceilings you impose on how much data flows through a stage per unit time. They work hand-in-hand with backpressure: when a stage hits its throughput limit (e.g., a database can only handle 1000 writes/sec), it stops accepting new input, triggering backpressure on upstream producers. This prevents cascading failures and ensures predictable resource usage.

Without backpressure and throughput controls, you lose observability and resilience. A streaming job may appear healthy until it suddenly runs out of memory and crashes mid-pipeline. Data may be dropped silently or reprocessed unpredictably. Backpressure forces you to declare "how fast can we actually go?" and makes slow consumers visible early.

## Practice

**Problem:** You are streaming job postings from a message queue into a data warehouse. Postings arrive at 5000/sec, but your warehouse can only ingest 500 inserts/sec without degrading. Without backpressure, your Kafka consumer will buffer all 5000/sec messages in memory, exhaust heap space, and crash.

**Solution:** Implement a throughput limit on the warehouse write stage and propagate backpressure to the consumer:

```sql
-- Track throughput limit in a control table
CREATE TABLE IF NOT EXISTS pipeline_control (
    stage_name VARCHAR PRIMARY KEY,
    max_throughput_per_sec INT,
    last_batch_size INT,
    last_batch_timestamp TIMESTAMP
);

INSERT INTO pipeline_control VALUES ('job_postings_ingest', 500, 0, CURRENT_TIMESTAMP);

-- Batch insert with backpressure: only write up to the limit per window
WITH current_batch AS (
    SELECT 
        job_id, job_title_short, salary_year_avg, 
        job_work_from_home, job_posted_date, job_location,
        ROW_NUMBER() OVER (ORDER BY job_posted_date ASC) as rn
    FROM staging_job_postings
    WHERE processed = FALSE
    LIMIT (SELECT max_throughput_per_sec FROM pipeline_control WHERE stage_name = 'job_postings_ingest')
)
INSERT INTO job_postings_fact
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM current_batch;

-- Signal Kafka consumer to pause if queue depth exceeds threshold
UPDATE pipeline_control 
SET last_batch_size = (SELECT COUNT(*) FROM staging_job_postings WHERE processed = FALSE),
    last_batch_timestamp = CURRENT_TIMESTAMP
WHERE stage_name = 'job_postings_ingest';

-- Consumer pauses if staging table > 2× throughput_per_sec
SELECT CASE 
    WHEN last_batch_size > (2 * max_throughput_per_sec) THEN 'PAUSE'
    ELSE 'CONTINUE'
END as consumer_signal
FROM pipeline_control
WHERE stage_name = 'job_postings_ingest';
```

## Notes

- **Confusing backpressure with retries:** Backpressure *prevents* failures by slowing input; retries *recover* from failures after they occur. Both are necessary but solve different problems.
- **Throughput limits must account for downstream dependencies:** A job posting ingest limit depends on warehouse write speed, network latency, and disk I/O. Measure actual capacity, don't guess.
- **Connects to:** circuit breakers (fail fast when downstream is saturated), consumer lag monitoring (how far behind the consumer is), and adaptive rate limiting (dynamically adjust limits based on system health).
- **Common mistake:** Setting throughput limits too high "to keep up" with peaks, then blaming the pipeline when it crashes. Set limits to what the slowest consumer can reliably handle under sustained load.
- **Revisit when:** Adding new downstream sinks, scaling consumer group size, or experiencing memory leaks in staging tables—these all change the effective throughput bottleneck.
