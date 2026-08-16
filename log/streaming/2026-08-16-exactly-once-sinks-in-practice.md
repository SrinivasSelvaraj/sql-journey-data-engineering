---
date: 2026-08-16
phase: streaming
topic: Exactly once sinks in practice
---

# Exactly once sinks in practice

*Streaming and distributed processing*

## Concept

Exactly-once semantics in sink systems means each record written to a downstream system (database, data warehouse, message queue) appears precisely once, regardless of how many times the stream processing engine internally retries or replays events. Without this guarantee, duplicate records accumulate silently—a job posting counted twice in aggregate metrics, salary statistics skewed by phantom entries, or compliance reports showing impossible totals.

The challenge emerges from the fundamental mismatch between stream processing's at-least-once delivery model (retries on failure) and storage systems' transactional boundaries. A task may crash after writing to the sink but before committing its checkpoint; on restart, the engine replays the same batch, and naive sinks write duplicates. True exactly-once requires idempotency: either the sink deduplicates using a unique key, or the system uses distributed transactions (two-phase commit) to make the write and checkpoint atomic.

In practice, exactly-once matters most for financial records, counts that feed alerts or SLAs, and fact tables in analytics. For append-only logs or exploratory dashboards, at-least-once with manual deduplication in queries is acceptable. But for a job postings fact table feeding hiring dashboards and reports, duplicates corrupt baseline metrics and erode trust in the data platform.

## Practice

**Problem:** A streaming job ingests job postings from a Kafka topic and writes to a PostgreSQL fact table. The job crashes mid-batch; on restart, some records are replayed. Without deduplication, salary_year_avg sums and job counts become inflated. How do you achieve exactly-once writes?

```sql
-- Solution: Upsert with unique constraint on (job_id, job_posted_date, insert_timestamp)
-- insert_timestamp marks when this stream instance wrote the record

CREATE TABLE job_postings_fact (
  job_id INT,
  job_title_short VARCHAR,
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR,
  insert_timestamp TIMESTAMP,
  PRIMARY KEY (job_id, job_posted_date, insert_timestamp)
);

-- Idempotent write: if record already exists, skip or update metadata only
INSERT INTO job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location, insert_timestamp)
VALUES 
  (123, 'Data Engineer', 145000, true, '2024-01-15', 'Remote', NOW())
ON CONFLICT (job_id, job_posted_date, insert_timestamp) 
DO NOTHING;  -- or DO UPDATE SET last_seen = NOW() if tracking freshness
```

## Notes

- **Deduplication key must be stable:** using only `job_id` is dangerous (same job posted twice legitimately); pairing with `job_posted_date` and `insert_timestamp` ensures replayed events are rejected without losing genuine duplicates.

- **Distributed transactions (two-phase commit) are slow:** frameworks like Flink offer them, but they significantly increase latency; idempotent writes via unique constraints are faster for most OLAP use cases.

- **Checkpoint offset coupling:** exactly-once guarantees only hold if the sink write and offset commit are tightly coupled; a crash between them still risks loss or duplication. Sinks must support transactional writes or state backends.

- **Adjacent concerns:** exactly-once interacts with late-arriving data (out-of-order events), windowing semantics (when does a job posting's salary aggregate finalize?), and eventual consistency in distributed systems.

- **Revisit when:** scaling to multiple sink instances (coordination overhead), switching storage (some systems like S3 have weaker transactional guarantees), or integrating external APIs that lack idempotency.
