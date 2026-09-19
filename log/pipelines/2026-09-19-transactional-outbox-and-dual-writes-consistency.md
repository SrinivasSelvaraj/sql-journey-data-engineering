---
date: 2026-09-19
phase: pipelines
topic: Transactional outbox and dual writes consistency
---

# Transactional outbox and dual writes consistency

*Pipelines and orchestration*

## Concept

The transactional outbox pattern solves a hard consistency problem: how do you atomically update your database *and* publish an event (or trigger a downstream pipeline) without risking lost messages or duplicate updates? Without it, you either update the database and fail to publish the event, or publish the event and crash before persisting the update. This matters anywhere you have critical state changes that downstream systems depend on—a job posting marked as closed needs to simultaneously update the fact table and trigger a notification pipeline, or your analytics and your alerts disagree on reality.

The dual writes anti-pattern (writing directly to both database and message queue) is seductive but broken: there's no atomicity guarantee across two systems, and when one fails partway through, you're left with inconsistent state that's hard to detect and repair. The outbox pattern fixes this by writing a single atomic transaction to your primary database: the actual state change *plus* an outbox table entry. A separate polling or CDC process then reads the outbox table and publishes events, decoupling the write from the publish. If the poll fails, you retry; if it succeeds, you mark the outbox record as processed.

Without this pattern, pipelines become fragile: you either lose events (data doesn't flow downstream), create duplicates (same event published twice), or ship stale data (database updated but event never fired). In data engineering, this means your job_postings_fact table and your notification queue disagree about what jobs are active, breaking downstream analytics and user-facing features.

## Practice

**Problem:** You need to update a job posting status from "active" to "closed" in your fact table *and* emit an event that triggers a notification pipeline to alert subscribers. If the update commits but the event publish fails, subscribers never get notified. If you publish first and the database update fails, your fact table is stale but the notification already fired.

```sql
-- Create outbox table to hold pending events
CREATE TABLE job_postings_outbox (
    outbox_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    job_id INT NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    event_payload JSON NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP NULL
);

-- Atomic transaction: update fact table AND write outbox entry
BEGIN TRANSACTION;

UPDATE job_postings_fact
SET job_posted_date = CURRENT_DATE
WHERE job_id = 42
  AND job_work_from_home = TRUE;

INSERT INTO job_postings_outbox (job_id, event_type, event_payload)
VALUES (
    42,
    'job_posting_closed',
    JSON_OBJECT(
        'job_id', 42,
        'job_title_short', 'Data Engineer',
        'closed_at', CURRENT_TIMESTAMP
    )
);

COMMIT;

-- Separate process polls and publishes (can retry safely):
SELECT outbox_id, event_payload
FROM job_postings_outbox
WHERE processed_at IS NULL
ORDER BY created_at ASC
LIMIT 100;

-- After successful publish to Kafka/event bus:
UPDATE job_postings_outbox
SET processed_at = CURRENT_TIMESTAMP
WHERE outbox_id IN (/* published ids */);
```

## Notes

- **Exactly-once semantics are hard**: Even with outbox, if your polling process crashes after publishing but before marking `processed_at`, you'll replay the event. Use idempotent consumers (deduplication keys) downstream to tolerate reruns.
- **CDC as an alternative**: PostgreSQL logical replication (Debezium, etc.) captures changes at the WAL level, eliminating the need to manually write an outbox table—but adds operational complexity; outbox is simpler for small-to-medium scale systems.
- **Polling vs. push trade-offs**: Polling the outbox table is simple but introduces latency (poll interval) and database load; event sourcing or Kafka CDC are faster but require more infrastructure.
- **Test failure modes explicitly**: Write tests that kill the polling process mid-publish, restart it, and verify deduplication. This is where real bugs hide—your happy path doesn't exercise the recovery loop.
- **Connects to**: event sourcing, idempotency tokens, distributed transactions, change data capture (CDC), and the broader concept of saga patterns for multi-step consistency.
