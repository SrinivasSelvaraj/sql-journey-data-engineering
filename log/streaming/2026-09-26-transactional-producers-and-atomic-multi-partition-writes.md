---
date: 2026-09-26
phase: streaming
topic: Transactional producers and atomic multi-partition writes
---

# Transactional producers and atomic multi-partition writes

*Streaming and distributed processing*

## Concept

A transactional producer ensures that multiple messages across different partitions are written atomically—either all succeed or all fail as a single unit. In Apache Kafka, this is enabled via the `enable.idempotence=true` and `transactional.id` producer configurations, which prevent duplicates and guarantee exactly-once semantics across partition writes. Without transactional guarantees, a producer crash mid-batch can leave data in an inconsistent state: some partitions receive messages while others don't, creating orphaned records that downstream consumers see out of sync.

This matters most when your streaming pipeline denormalizes or correlates data across multiple partitions. For example, if you're publishing job posting events to one partition and salary update events to another, a partial write failure means a consumer might see a job without its corresponding salary update, violating application invariants. Without atomicity, you'd need expensive downstream deduplication logic and manual reconciliation.

The cost is throughput: transactional producers serialize writes and add coordination overhead with the broker. The benefit is correctness—you avoid the "phantom record" problem where a retry produces duplicates, and you sidestep cascading corruption in stateful downstream systems (stream joins, aggregations, materialized views).

## Practice

**Problem:** You are publishing enriched job postings to Kafka. For each posting, you must atomically write three messages: (1) the fact record to partition 0, (2) a salary alert event to partition 1 (if salary > 150k), and (3) a location index event to partition 2. If the producer crashes after writing partition 0 but before partition 1, consumers see incomplete data. Model this atomic write.

```sql
-- Producer-side configuration (pseudo-code / Kafka properties)
-- properties.put("enable.idempotence", "true");
-- properties.put("transactional.id", "job-enricher-1");
-- properties.put("acks", "all");
-- properties.put("retries", Integer.MAX_VALUE);

-- Transactional write logic (Java/Python pseudocode):
BEGIN_TRANSACTION
  SEND job_postings_fact 
    (job_id=101, job_title_short='Data Engineer', salary_year_avg=145000, 
     job_work_from_home=true, job_posted_date='2025-01-15', job_location='Remote')
    TO partition 0

  IF salary_year_avg > 150000 THEN
    SEND salary_alert_event 
      (job_id=101, salary_year_avg, alert_type='high_pay')
      TO partition 1
  END IF

  SEND location_index_event 
    (job_id=101, job_location='Remote', indexed_date='2025-01-15')
    TO partition 2

COMMIT_TRANSACTION
-- On failure, all three messages are rolled back; consumer sees nothing.
```

## Notes

- **Idempotence vs. transactionality:** `enable.idempotence=true` alone prevents duplicates within a single send(), but does not guarantee atomicity across multiple partitions—you need `transactional.id` for that. Confusing the two is a common mistake.
- **Consumer isolation level matters:** Set `isolation.level=read_committed` on consumers to ensure they only see transactionally written messages; `read_uncommitted` (default) may expose aborted/partial writes.
- **Transactional ID must be stable:** Use a static `transactional.id` per producer instance (e.g., hostname + process ID). Changing it breaks exactly-once guarantees and can cause zombie fencing issues.
- **Adjacent concepts:** Exactly-once semantics (EOS), consumer group offset commits (also transactional), and stream processing frameworks like Kafka Streams that manage transactions internally.
- **Performance trade-off:** Transactional writes reduce throughput by ~30–50% due to two-phase commit overhead. Reserve this for correctness-critical pipelines; high-volume telemetry may not need it.
