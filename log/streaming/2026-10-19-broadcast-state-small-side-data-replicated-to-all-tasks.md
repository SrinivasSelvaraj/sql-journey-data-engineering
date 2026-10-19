---
date: 2026-10-19
phase: streaming
topic: Broadcast state: small side data replicated to all tasks
---

# Broadcast state: small side data replicated to all tasks

*Streaming and distributed processing*

## Concept

Broadcast state is a pattern where small, reference data (typically a lookup table or configuration) is replicated across all parallel task instances in a distributed streaming job. Instead of joining a stream against a large external table on every record—which creates I/O bottlenecks—you load the reference data once into memory on each task and perform fast, local lookups.

This matters most when you have a stream of millions of events that need enrichment from a slowly-changing dimension (job titles, currency rates, location hierarchies). Without broadcast state, you either make expensive network calls per event, or you risk inconsistency if different tasks see different versions of the reference data at different times.

What breaks: latency spikes from external lookups, memory waste from redundant I/O across tasks, and synchronization gaps when the reference data updates—some tasks might see v1 while others see v2 mid-stream.

## Practice

**Problem:** A stream of job applications arrives continuously. You need to enrich each application with the current salary range for its job_id, sourced from job_postings_fact. The fact table updates hourly, but you cannot afford a network lookup per application.

```sql
-- Broadcast the lookup table into state at job start
-- (pseudocode pattern for frameworks like Flink/Spark Streaming)

-- In your streaming job initialization:
CREATE OR REPLACE VIEW job_salary_broadcast AS
  SELECT job_id, job_title_short, salary_year_avg
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY;

-- In your stream processing logic (e.g., Flink):
-- broadcast_state = env.addSource(...)
--   .map(new BroadcastMapFunction() {
--     On OPEN: load job_salary_broadcast into HashMap<job_id, salary>
--     On MAP: look up salary locally, emit enriched record
--   })

-- Stream in: application_id, job_id, applied_date
-- Enriched output: application_id, job_id, applied_date, salary_year_avg (from broadcast)
```

## Notes

- **Stale data trap:** broadcast state is "eventually consistent"—a 1-hour refresh window means queries may use outdated salary ranges. Document the acceptable staleness.
- **Size matters:** broadcast only fits data that fits in task memory; if your reference table is 10GB+, use a broadcast-optimized join or external lookup service instead.
- **Connects to:** stateful processing, windowed joins, and slowly-changing dimensions (SCD Type 2). Also adjacent to changelog streams, where reference data changes are streamed in as events.
- **Testing gotcha:** simulate reference data updates during integration tests; verify all tasks pick up the new version atomically.
- **Revisit:** compare broadcast state against keyed state (per-key snapshots) and external state backends (Redis, HBase) based on latency, consistency, and data volume trade-offs.
