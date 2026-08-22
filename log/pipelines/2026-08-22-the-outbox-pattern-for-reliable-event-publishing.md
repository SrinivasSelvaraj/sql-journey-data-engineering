---
date: 2026-08-22
phase: pipelines
topic: The outbox pattern for reliable event publishing
---

# The outbox pattern for reliable event publishing

*Pipelines and orchestration*

## Concept

The outbox pattern solves a critical problem: how do you publish an event *and* update your database in the same atomic transaction? Without it, you risk either losing events (if the event system fails after your database commit) or publishing duplicates (if your database fails after the event system succeeds). The pattern works by writing both your data change *and* the event to the same database in one transaction, then having a separate process poll the outbox table and reliably ship events downstream.

This matters most in event-driven pipelines where downstream systems (analytics, notifications, other services) depend on receiving every event exactly once. In a data warehouse context, it's essential when you're both updating a fact table and emitting events that trigger dependent transformations—missing or duplicated events corrupt your data lineage. Without the outbox pattern, you'll encounter silent failures: a job posting fact gets inserted but the event never reaches your orchestration layer, leaving dependent jobs unscheduled or stale.

The pattern requires discipline: your application writes to the outbox table in the same transaction as your primary data write, then a polling service (or CDC tool) consumes from the outbox asynchronously. This decouples the speed and reliability of your database from the speed and reliability of your message broker.

## Practice

**Problem:** You're inserting new job postings into `job_postings_fact` and need to reliably trigger downstream aggregation jobs. If the insert succeeds but the event never publishes, your aggregations stay stale. If the event publishes but the insert fails, you'll aggregate phantom data.

```sql
-- Step 1: Create an outbox table in the same schema
CREATE TABLE job_postings_outbox (
  outbox_id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  event_type VARCHAR(50) NOT NULL,
  aggregate_id INT NOT NULL,
  payload JSONB NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  published_at TIMESTAMP,
  job_id INT NOT NULL
);

-- Step 2: Insert job posting and emit event in one transaction
BEGIN TRANSACTION;

INSERT INTO job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
VALUES 
  (5847, 'Data Engineer', 125000, TRUE, '2024-01-15', 'Remote');

INSERT INTO job_postings_outbox 
  (event_type, aggregate_id, payload, job_id)
VALUES 
  ('JobPostingCreated', 5847, 
   jsonb_build_object(
     'job_id', 5847,
     'job_title_short', 'Data Engineer',
     'salary_year_avg', 125000,
     'event_time', CURRENT_TIMESTAMP
   ), 5847);

COMMIT;

-- Step 3: Polling query (run periodically or via CDC)
-- Publish and mark as sent
UPDATE job_postings_outbox 
SET published_at = CURRENT_TIMESTAMP
WHERE published_at IS NULL
  AND created_at < CURRENT_TIMESTAMP - INTERVAL '5 seconds'
RETURNING outbox_id, event_type, payload, job_id;

-- Cleanup (after confirming downstream ack)
DELETE FROM job_postings_outbox 
WHERE published_at IS NOT NULL 
  AND published_at < CURRENT_TIMESTAMP - INTERVAL '7 days';
```

## Notes

- **Idempotency is non-negotiable:** the polling service may publish the same event twice if it crashes between sending and marking it published. Your downstream consumers must deduplicate on `(aggregate_id, event_type, created_at)`.
- **Outbox lag becomes observable:** monitor the age of unpublished rows in the outbox table; this is your "time to publication" metric and a leading indicator of pipeline problems.
- **Connects to CDC (Change Data Capture):** for high-volume systems, replace polling with Postgres logical decoding or Debezium; the outbox table remains the same, just the ingestion method changes.
- **Watch transaction isolation:** if your polling query runs in READ UNCOMMITTED or READ COMMITTED, you may miss rows or see phantom publishes; use READ COMMITTED with explicit locking or READ REPEATABLE ISOLATION.
- **Revisit when adding retry logic:** if an event fails to publish downstream, you need a dead-letter queue and manual intervention strategy; the outbox pattern doesn't handle that automatically.
