---
date: 2026-10-13
phase: pipelines
topic: At-least-once delivery: fault tolerance trade-offs
---

# At-least-once delivery: fault tolerance trade-offs

*Pipelines and orchestration*

## Concept

At-least-once delivery guarantees that every message or event processed by a pipeline will be acted upon, even if the system crashes mid-execution. This is achieved by decoupling message consumption from result commit: consume the message, process it, *then* mark it complete only after the result is safely written. If a worker dies between processing and commit, the message is reprocessed—but the output must be idempotent (safe to repeat) to avoid duplicates in your data warehouse.

This matters enormously in data pipelines because source systems are unreliable (API timeouts, network partitions) and so are your infrastructure (container restarts, disk fills). Without at-least-once guarantees, you silently lose events: a job posting ingests, crashes before INSERT, and disappears. Your fact table has gaps that nobody notices until the business asks "why did hiring drop 15% on March 3rd?"

What breaks: exactly-once semantics are expensive (distributed transactions, global consensus). At-most-once is cheap but loses data. At-least-once is the pragmatic middle ground—it requires you to make your writes idempotent and your retries safe.

## Practice

**Problem:** Your job postings pipeline consumes from an API, transforms records, and writes to `job_postings_fact`. A worker crashes after fetching 50 new postings but before committing the transaction. On restart, the API gives you the same 50 records again. How do you avoid duplicate rows?

```sql
-- Use an upsert pattern with a unique constraint on the natural key
-- This makes the write idempotent: replaying the same records updates, not duplicates

CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR(50),
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(100),
  _loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  _batch_id VARCHAR(50) NOT NULL
);

-- On every batch (retry-safe):
INSERT INTO job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location, _batch_id)
VALUES 
  (101, 'Data Engineer', 120000, TRUE, '2025-01-15', 'Remote', 'batch_20250115_001'),
  (102, 'Analytics Lead', 135000, FALSE, '2025-01-15', 'New York, NY', 'batch_20250115_001')
ON CONFLICT (job_id) 
DO UPDATE SET 
  salary_year_avg = EXCLUDED.salary_year_avg,
  job_location = EXCLUDED.job_location,
  _loaded_at = CURRENT_TIMESTAMP
WHERE job_postings_fact._batch_id != EXCLUDED._batch_id;
-- Only update if this is a new batch, avoiding phantom re-updates
```

## Notes

- **Deduplication is your responsibility.** At-least-once doesn't mean your fact table isn't duplicated; it means your system *will* retry. Use `ON CONFLICT` (Postgres), `MERGE` (T-SQL), or idempotent keys in your application logic. Store `_batch_id` or `_processed_at` to detect replays.

- **Offset management is critical.** In Kafka/message queues, only commit the consumer offset *after* the database transaction succeeds. If you commit offset then crash, you lose that batch. Reverse the order and you replay—annoying but safe.

- **Retries can amplify bugs.** If your transform logic is broken, at-least-once means you'll insert bad data *multiple times*. Add schema validation and data quality checks *before* the write, not after. Monitor `_batch_id` cardinality to catch reprocessing loops.

- **Connects to:** exactly-once semantics (expensive, rarely needed), idempotency keys, transactional outbox pattern, monitoring lag and replay rates.

- **Revisit when:** designing SLAs, tuning retry policies (exponential backoff vs. fixed), or investigating why a metric spiked—first question is always "did we replay a batch?"
