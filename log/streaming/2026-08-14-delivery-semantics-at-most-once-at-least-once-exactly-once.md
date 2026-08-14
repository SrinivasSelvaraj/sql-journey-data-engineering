---
date: 2026-08-14
phase: streaming
topic: Delivery semantics: at most once, at least once, exactly once
---

# Delivery semantics: at most once, at least once, exactly once

*Streaming and distributed processing*

## Concept

Delivery semantics define the guarantee a system makes about how many times a message or event will be processed. **At most once** means a message may be lost but never duplicated; **at least once** means a message is never lost but may be duplicated; **exactly once** means each message is processed precisely one time. These guarantees become critical in streaming systems because source failures, network partitions, and consumer crashes can cause retries and reprocessing. Without clear semantics, you risk either losing revenue data (at most once), double-counting metrics (at least once), or building complex, costly deduplication logic (pursuing exactly once).

The choice depends on your tolerance for data loss versus complexity. Financial transactions demand exactly once. Analytics dashboards often accept at least once with deduplication on the consumer side. IoT sensor telemetry might tolerate at most once if individual readings are low-value. Most cloud streaming platforms (Kafka, Kinesis, Pub/Sub) default to at least once; you must design your pipeline to handle duplicates or add idempotency.

## Practice

**Problem:** A job board ingests job_postings_fact events from multiple recruiters. The Kafka topic is configured for at-least-once delivery. You need to count unique jobs posted per day without double-counting duplicates that arrive from retries.

```sql
-- Idempotent insert using job_id as unique key
-- Assumes events contain: job_id (unique), job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location

INSERT INTO job_postings_fact (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM staging_kafka_events
ON CONFLICT (job_id) DO NOTHING;

-- Then safely aggregate without duplicates
SELECT 
  job_posted_date,
  COUNT(DISTINCT job_id) as unique_jobs_posted,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
GROUP BY job_posted_date;
```

## Notes

- **Idempotency is your friend:** Design consumers with unique keys (job_id, transaction_id, event_id) and upsert/merge logic; exactly-once guarantees are expensive and often unnecessary if your writes are already idempotent.
- **Deduplication window:** At-least-once systems need a deduplication window (e.g., 24 hours of seen event IDs); events older than the window cannot be deduplicated safely, so define retention accordingly.
- **Source vs. consumer responsibility:** Some systems (e.g., Kafka with transactions) push semantics to the broker; others (Kinesis) leave it to the application. Know where your guarantee ends.
- **Exactly-once pitfall:** Pursuing true exactly-once often requires distributed transactions or compensating logic across state stores, adding latency and operational complexity; measure whether the cost is justified.
- **Connects to:** Checkpointing, offset management, idempotent keys, outbox pattern, and CDC (Change Data Capture) for sourcing data reliably from databases.
