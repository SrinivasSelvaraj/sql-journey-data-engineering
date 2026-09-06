---
date: 2026-09-06
phase: streaming
topic: Kafka: exactly-once semantics and transactions
---

# Kafka: exactly-once semantics and transactions

*Streaming and distributed processing*

## Concept

Exactly-once semantics (EOS) in Kafka guarantees that each message is processed and committed exactly once, even in the face of producer retries, consumer crashes, or broker failures. Without it, you risk duplicate processing (at-least-once) or data loss (at-most-once). This matters because financial transactions, inventory deductions, or billing events cannot tolerate duplicates—processing the same job application twice or charging a customer twice is not recoverable by downstream logic alone.

Kafka achieves EOS through idempotent producers, transactional writes, and transactional reads. The producer assigns a sequence number to each message and detects retries; the broker deduplicates before committing. On the consumer side, offsets and output writes must be atomic—both succeed or both roll back—so a crash mid-processing doesn't leave you with a committed offset but no output, or vice versa.

The catch: EOS requires coordination overhead (latency, throughput cost) and assumes your downstream system is also transactional (or your writes are idempotent). If you write to a non-transactional sink without deduplication logic, EOS is broken at the application layer.

## Practice

**Problem:** A stream of job postings arrives in Kafka. You must update a fact table with salary and location, but your pipeline crashes mid-batch. You need to ensure no duplicate salary calculations or double-counted job postings in your aggregation metrics.

```sql
-- Producer configuration (idempotent + transactional)
-- enable.idempotence=true
-- transactional.id=job-posting-pipeline-1
-- acks=all

-- Consumer configuration
-- isolation.level=read_committed (only read committed messages)
-- enable.auto.commit=false (manual commit with offset)

-- Application logic (pseudo-code pattern):
BEGIN TRANSACTION
  -- Read from Kafka with offset tracking
  messages = consumer.poll(timeout=5000)
  
  FOR each message IN messages:
    UPSERT INTO job_postings_fact 
    VALUES (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
    ON CONFLICT (job_id) DO UPDATE 
      SET salary_year_avg = EXCLUDED.salary_year_avg,
          job_location = EXCLUDED.job_location
  
  -- Commit offset only after all writes succeed
  consumer.commitSync(offsets)
COMMIT TRANSACTION
-- On exception, ROLLBACK; no offset commit, message reprocessed
```

Key: the `ON CONFLICT DO UPDATE` makes the upsert idempotent—reprocessing the same message produces the same final state, not duplicates.

## Notes

- **Idempotence vs. transactions:** Idempotence (same input → same output) is a property of your code; transactions are a Kafka feature. Use both: Kafka ensures delivery once, your logic ensures the operation is side-effect-free.
- **Performance trade-off:** EOS adds latency (batching, coordination) and reduces throughput. Profile your latency SLA before enabling; sometimes at-least-once with idempotent writes is a pragmatic choice.
- **State store durability:** If using Kafka Streams with local state stores, enable changelog topics and configure `processing.guarantee=exactly_once_v2` (newer, faster than v1). State store loss means reprocessing the entire stream from the beginning.
- **Offset + output atomicity:** The most common mistake is committing offsets before writing to the sink. Always commit after successful output, or use transactional sinks (Postgres, MySQL with XA) to ensure both change together.
- **Connects to:** Kafka Streams exactly-once processing, CDC patterns, and two-phase commit / XA transactions in databases.
