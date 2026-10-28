---
date: 2026-10-28
phase: pipelines
topic: Sensor patterns: polling vs event-driven
---

# Sensor patterns: polling vs event-driven

*Pipelines and orchestration*

## Concept

Polling and event-driven are two fundamental patterns for detecting changes in source systems. **Polling** means your pipeline periodically queries a source (every N minutes/hours) to check for new or modified records—simple but creates latency and wastes compute on unchanged data. **Event-driven** means the source actively pushes notifications (via Kafka, webhooks, database triggers) when changes occur, triggering your pipeline only when needed.

The choice shapes pipeline economics and freshness. Polling works well for batch-oriented systems and gives you full control over retry logic, but introduces staleness windows and query load on the source. Event-driven cuts latency to near-real-time and reduces wasted scanning, but requires the source system to emit reliable events and your pipeline to handle out-of-order or duplicate messages gracefully.

Without understanding this distinction, you either over-poll (hammering the source, missing real-time requirements) or under-architect events (losing messages, creating silent failures). In data pipelines that "fail loudly," you must choose deliberately: if you poll, set explicit SLAs for lag; if you go event-driven, instrument offset tracking and dead-letter queues so failures don't vanish.

## Practice

**Problem:** You maintain an ETL that populates `job_postings_fact` from a transactional HR system updated throughout the day. Currently you poll the source table every 6 hours, but stakeholders complain about missing same-day salary updates. You need to catch changes faster without hammering the source.

```sql
-- Event-driven approach: capture changes via a change-data-capture log
-- Assume source system writes change events to a kafka topic or CDC table

WITH cdc_events AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    event_timestamp,
    event_type, -- INSERT, UPDATE, DELETE
    ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY event_timestamp DESC) AS rn
  FROM source_system.job_postings_cdc
  WHERE event_timestamp > CURRENT_TIMESTAMP - INTERVAL '5 minutes'
    AND processed_flag = FALSE
)
MERGE INTO job_postings_fact AS target
USING cdc_events AS source
  ON target.job_id = source.job_id AND source.rn = 1
WHEN MATCHED AND source.event_type = 'UPDATE' THEN
  UPDATE SET
    salary_year_avg = source.salary_year_avg,
    job_work_from_home = source.job_work_from_home
WHEN MATCHED AND source.event_type = 'DELETE' THEN
  DELETE
WHEN NOT MATCHED AND source.event_type IN ('INSERT', 'UPDATE') THEN
  INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
  VALUES (source.job_id, source.job_title_short, source.salary_year_avg, source.job_work_from_home, source.job_posted_date, source.job_location);

-- Mark CDC events as processed only after successful merge
UPDATE source_system.job_postings_cdc
SET processed_flag = TRUE, processed_at = CURRENT_TIMESTAMP
WHERE event_timestamp <= CURRENT_TIMESTAMP - INTERVAL '5 minutes'
  AND processed_flag = FALSE;
```

## Notes

- **Hybrid approach:** Many mature pipelines use *polling for discovery* (periodic full scan to catch orphaned records) + *events for velocity* (Kafka/CDC for real-time changes). This catches both steady-state and anomalies.

- **Duplicate and ordering hazards:** Event-driven systems can emit the same change twice or out of sequence, especially after restarts. Always use idempotent merges (row-number windowing, deduplication keys) and offset tracking to resume safely.

- **Monitoring lag:** With polling, lag is deterministic (6-hour window known upfront); with events, you must actively monitor consumer lag, dead-letter queues, and event payload health. Silent lag is worse than loud lag.

- **Source system coupling:** Event-driven ties your pipeline to source infrastructure (Kafka cluster, trigger availability). Polling is looser but slower. Trade-off explicitness for flexibility based on your SLA.

- **Relates to:** idempotency and exactly-once semantics, watermarking and late-arriving data, orchestration retry strategies (Airflow backfill, dbt retry), and instrumentation (logging processed offsets, alerting on lag thresholds).
