---
date: 2026-11-01
phase: streaming
topic: Exactly-once semantics and deduplication
---

# Exactly-once semantics and deduplication

*Streaming and distributed processing*

## Concept

Exactly-once semantics (EOS) means each event is processed and its effects are recorded precisely one time—no duplicates, no loss. In streaming systems, failures are inevitable: network timeouts, process crashes, broker rebalancing. Without exactly-once, a failed message might be retried and processed twice, or a system restart might replay data. With multiple partitions and parallel consumers, duplicates compound across the cluster.

This matters most when processing affects state: incrementing counters, updating aggregates, writing to a warehouse, or triggering downstream actions. A duplicate salary record could inflate average salary calculations; a duplicate job posting could skew job market analysis. Deduplication—identifying and discarding repeated events—is the practical implementation, typically using an idempotency key (a unique identifier for the logical operation) and a state store or database that detects replays.

Without exactly-once, audit trails become unreliable, financial calculations drift, and downstream reports lose credibility. The cost of a single undetected duplicate compounds through dependent systems.

## Practice

**Problem:** A stream of job postings arrives from an external API. The same job posting can be delivered multiple times due to network retries. You need to count distinct jobs posted per day without duplicates inflating the totals, and load facts into a warehouse.

```sql
-- Deduplication using a surrogate key and state table
-- Assume incoming stream has: job_id, job_title_short, salary_year_avg, 
--                              job_work_from_home, job_posted_date, job_location

CREATE TABLE job_postings_dedup_state (
  job_id INT,
  posted_date DATE,
  hash_value VARCHAR,
  processed_at TIMESTAMP,
  PRIMARY KEY (job_id, posted_date)
);

-- On each event arrival, compute hash of full record
WITH incoming AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    MD5(CONCAT(job_id, job_title_short, salary_year_avg, 
               job_work_from_home, job_posted_date, job_location)) AS record_hash
)
-- Only insert if this (job_id, posted_date, hash) is new
MERGE INTO job_postings_dedup_state t
USING incoming i
  ON t.job_id = i.job_id AND t.posted_date = i.job_posted_date
WHEN NOT MATCHED THEN
  INSERT (job_id, posted_date, hash_value, processed_at)
  VALUES (i.job_id, i.job_posted_date, i.record_hash, CURRENT_TIMESTAMP)
WHEN MATCHED AND t.hash_value = i.record_hash THEN
  -- Same record seen again: skip
  UPDATE SET processed_at = CURRENT_TIMESTAMP;

-- Load only deduplicated records to fact table
INSERT INTO job_postings_fact
SELECT DISTINCT i.* FROM incoming i
INNER JOIN job_postings_dedup_state s
  ON i.job_id = s.job_id AND i.job_posted_date = s.posted_date
WHERE i.record_hash = s.hash_value;
```

## Notes

- **Idempotency key design matters**: Use business keys (job_id + posted_date) rather than timestamps alone; timestamps can collide under concurrent retries.
- **Hash/checksum validation**: Store a hash of the full record to detect duplicates *and* silent corruption; a duplicate with changed salary should fail validation.
- **State store overhead**: Dedup state grows unbounded unless you purge old records; use TTL or sliding windows keyed to event time, not wall-clock time.
- **Connects to**: transactional writes, exactly-once source connectors (Kafka, Kinesis guarantees), idempotent operators in Flink/Spark, and consumer group offset management.
- **Revisit**: the difference between at-most-once, at-least-once, and exactly-once delivery guarantees; when exactly-once is overkill (non-idempotent sinks don't benefit).
