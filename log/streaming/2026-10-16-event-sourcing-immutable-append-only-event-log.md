---
date: 2026-10-16
phase: streaming
topic: Event sourcing: immutable append-only event log
---

# Event sourcing: immutable append-only event log

*Streaming and distributed processing*

## Concept

Event sourcing treats your data system as an immutable append-only log of events—each change is recorded as a new entry rather than overwriting state. This is critical in streaming contexts because events arrive out of order, duplicate, or with delays; an append-only log preserves causality and lets you reconstruct state at any point in time. Without immutability, you lose the ability to audit what happened, recover from logic errors by replaying events, or handle late-arriving corrections that would have changed earlier decisions.

In distributed systems, immutability eliminates write conflicts and replay races. If job posting `JP-001` gets updated three times across different servers, an append-only log records all three as distinct events; you replay them in order to derive the correct current state. This is far simpler than trying to merge conflicting updates to a single mutable record.

The cost is storage and compute: you must process the entire event history to answer "what is the current state?" This is why event sourcing pairs with snapshots or materialized views—you periodically checkpoint the derived state so you don't replay millions of events every query.

## Practice

**Problem:** Job postings are updated frequently (salary adjustments, location changes, remote status corrections). You need to track *when* each attribute changed and *what the full posting looked like* at any historical date, even when updates arrive out of order. How do you design for this?

**Solution:** Create an immutable events table and derive current state via a materialized view or snapshot.

```sql
-- Immutable event log (append-only)
CREATE TABLE job_posting_events (
  event_id BIGINT PRIMARY KEY,
  job_id VARCHAR NOT NULL,
  event_type VARCHAR NOT NULL,  -- 'created', 'updated', 'deleted'
  event_timestamp TIMESTAMP NOT NULL,
  event_received_timestamp TIMESTAMP NOT NULL,  -- when we saw it
  job_title_short VARCHAR,
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_location VARCHAR,
  posted_date DATE
);

-- Derive current state by taking the latest non-null value per attribute
CREATE MATERIALIZED VIEW job_postings_current AS
  SELECT
    job_id,
    COALESCE(
      (SELECT job_title_short FROM job_posting_events 
       WHERE job_posting_events.job_id = e.job_id AND job_title_short IS NOT NULL 
       ORDER BY event_timestamp DESC LIMIT 1),
      NULL
    ) AS job_title_short,
    -- Repeat for each field...
    salary_year_avg,
    job_work_from_home,
    job_location
  FROM (SELECT DISTINCT job_id FROM job_posting_events) e;

-- Query history: reconstruct state as of any date
SELECT job_id, job_title_short, salary_year_avg
FROM job_posting_events
WHERE event_timestamp <= '2024-01-15'::TIMESTAMP
  AND job_id = 'JP-001'
ORDER BY event_timestamp DESC
LIMIT 1;
```

## Notes

- **Snapshot anti-pattern:** Don't discard old events after taking a snapshot. Keep the full log; snapshots are optimization only. If you lose events, you lose auditability and the ability to replay with corrected logic.

- **Late arrivals and out-of-order handling:** The `event_received_timestamp` is different from `event_timestamp`—crucial when a job update from 3 hours ago arrives now. Process by `event_timestamp`, not receipt order.

- **Temporal queries and slowly changing dimensions (SCD):** Event sourcing is a natural fit for SCD Type 2 (tracking historical versions). Each event is a dimension record; you join on effective_date ranges rather than snapshots.

- **Stream processing integration:** Tools like Kafka + Flink or Spark Structured Streaming consume the event log in real-time, aggregate into windows, and materialize views. The immutable log is your source of truth.

- **Revisit:** Idempotency (handling duplicate events) and event schema evolution (adding fields to old events without breaking replay logic) are hard problems that grow as systems age.
