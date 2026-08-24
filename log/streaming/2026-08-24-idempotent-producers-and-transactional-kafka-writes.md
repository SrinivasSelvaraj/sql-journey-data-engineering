---
date: 2026-08-24
phase: streaming
topic: Idempotent producers and transactional Kafka writes
---

# Idempotent producers and transactional Kafka writes

*Streaming and distributed processing*

## Concept

Idempotent producers guarantee that a message sent multiple times to Kafka results in exactly one write, eliminating duplicates caused by retries. When a producer doesn't receive an acknowledgment, it retries—but the broker may have already written the message. Without idempotency, you get duplicate records in your stream. Transactional writes extend this: they allow a producer to write multiple messages atomically, ensuring either all succeed or none do, critical when a single logical event (like a job posting update) spans multiple topics or partitions.

In streaming data pipelines, duplicates compound downstream. A job posting ingested twice inflates metrics, breaks aggregations, and corrupts analytics. Idempotent producers use a producer ID and sequence number per partition; the broker detects and discards retried messages. Transactional producers add an epoch and control messages, letting consumers read only committed data—preventing partial writes from appearing mid-stream when a producer crashes mid-transaction.

Without these guarantees, distributed failures (network timeouts, broker restarts, producer crashes) force you to choose between data loss and duplicates. Idempotency and transactions shift that burden to Kafka itself, not your application code.

## Practice

**Problem:** A job posting service produces job records to Kafka and also writes a summary metric (total salary budget per location) atomically. A network failure causes the producer to retry after the posting succeeded but before the metric was sent. You must prevent duplicate postings and ensure the metric always matches the posting count.

```sql
-- Producer configuration (pseudo-code / settings)
-- properties.put("enable.idempotence", "true");
-- properties.put("transactional.id", "job-posting-producer-1");
-- properties.put("acks", "all");

-- In application logic:
BEGIN TRANSACTION
  SEND message TO topic "job_postings" PARTITION job_location 
    WITH (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
  
  SEND message TO topic "location_salary_metrics" PARTITION job_location
    WITH (location, total_salary_added = salary_year_avg)
COMMIT TRANSACTION

-- Consumer sees both or neither; duplicate retries are silently dropped by broker
```

## Notes

- **Enable idempotence first**: Set `enable.idempotence=true` and `acks=all` before transactions; it's the foundation and low-cost safeguard against duplicate messages.
- **Transactional ID must be stable**: If you run multiple producer instances, each needs a unique `transactional.id` that persists across restarts; reusing the same ID after a crash aborts pending transactions from the old instance.
- **Consumer isolation level matters**: Set `isolation.level=read_committed` to skip uncommitted messages; `read_uncommitted` reads in-flight data and defeats the purpose of transactions.
- **Common mistake**: Confusing idempotence (single message retried) with transactions (multi-message atomicity); you need both for full exactly-once semantics in multi-topic pipelines.
- **Related topics**: Exactly-once semantics (EOS), offset management, and consumer group coordination; also connect to dead-letter queues for handling messages that fail after retries.
