---
date: 2026-09-19
phase: pipelines
topic: Event sourcing and event store append-only logs
---

# Event sourcing and event store append-only logs

*Pipelines and orchestration*

## Concept

Event sourcing treats an append-only log as the single source of truth: instead of storing current state (a job posting's salary), you store every state change as an immutable event (salary_updated, job_republished, job_closed). Each event carries a timestamp and payload. When you need the present state, you replay events forward from a chosen point.

This matters for pipelines because replaying is deterministic and debuggable—you can fix a broken transformation, rerun from event N without losing history, and audit exactly what changed and when. Without it, you overwrite facts, lose causality, and can't explain why your dashboard shows what it does. A job posting's salary changed three times; which version did your report use? The log knows.

Event sourcing breaks when you don't enforce immutability (someone UPDATEs an old row), skip timestamps or ordering info, or mix events with snapshots carelessly. It also compounds cost if you log too granularly (every keystroke) without pruning or snapshots.

## Practice

**Problem:** Your job_postings_fact table is loaded nightly from a CSV, but when salary corrections arrive mid-week, the old numbers vanish. Your dashboard uses yesterday's report and shows stale data. You can't prove which salary was live when, and reruns wipe history.

**Solution:** Create an immutable events table and rebuild fact tables from it:

```sql
CREATE TABLE job_postings_events (
  event_id BIGINT PRIMARY KEY,
  job_id INT NOT NULL,
  event_type VARCHAR(50) NOT NULL, -- posted, salary_updated, closed, reposted
  event_timestamp TIMESTAMP NOT NULL,
  payload JSONB NOT NULL, -- {job_title_short, salary_year_avg, job_work_from_home, job_location, job_posted_date}
  inserted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Immutable insert only
INSERT INTO job_postings_events (job_id, event_type, event_timestamp, payload)
VALUES (
  12345,
  'salary_updated',
  '2025-01-15 09:30:00',
  '{"salary_year_avg": 125000, "job_title_short": "Data Engineer"}'::JSONB
);

-- Rebuild fact table by replaying events up to a point
CREATE TABLE job_postings_fact AS
SELECT DISTINCT ON (job_id)
  (payload->>'job_id')::INT AS job_id,
  payload->>'job_title_short' AS job_title_short,
  (payload->>'salary_year_avg')::INT AS salary_year_avg,
  (payload->>'job_work_from_home')::BOOLEAN AS job_work_from_home,
  payload->>'job_location' AS job_location,
  payload->>'job_posted_date' AS job_posted_date
FROM job_postings_events
WHERE event_timestamp <= '2025-01-14 23:59:59' -- replay to a known-good point
ORDER BY job_id, event_timestamp DESC;
```

## Notes

- **Immutability is non-negotiable:** use append-only tables, block UPDATEs/DELETEs with constraints or row-level security, and treat events as write-once.
- **Timestamps and ordering:** always include event_timestamp and a global sequence (event_id); without ordering, replay is meaningless. Distribute clock skew across services is a common pitfall.
- **Snapshots reduce replay cost:** store a materialized state every N events or time period so you don't replay millions of events on every pipeline run; pair with event log retention policies.
- **Bridges to adjacent topics:** CQRS (Command Query Responsibility Segregation) separates writes (events) from reads (materialized views); CDC (Change Data Capture) is the inverse—extract events from a mutable DB; idempotency keys ensure rerun-safety.
- **Revisit schema evolution:** as event payloads grow, versioning and backward compatibility matter; JSONB flexibility helps, but document breaking changes.
