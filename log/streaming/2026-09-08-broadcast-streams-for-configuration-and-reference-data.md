---
date: 2026-09-08
phase: streaming
topic: Broadcast streams for configuration and reference data
---

# Broadcast streams for configuration and reference data

*Streaming and distributed processing*

## Concept

Broadcast streams distribute slowly-changing reference data (lookup tables, configs, dimension tables) to all parallel instances of a streaming job so they can enrich fast-moving event streams without causing backpressure or network bottlenecks. Instead of joining a high-throughput event stream directly to a remote database on every record, you materialize the reference data locally in each task, update it periodically from a broadcast channel, and perform in-memory lookups.

This matters because streaming joins are expensive: each event that needs enrichment creates latency and stress on the reference system. Broadcast streams are critical when you have a high-volume fact stream (millions of events/sec) joining against slowly-changing dimensions (updated hourly or daily). Without broadcasts, you either serialize network calls or risk consistency issues from stale caches.

The pattern breaks down when reference data is too large to fit in memory on each worker, or when it must be updated with sub-second latency. In those cases, you trade memory for a dedicated external state store (Redis, DynamoDB) or use a keyed stream join with an explicit state backend.

## Practice

**Problem:** You have a stream of job applications arriving at high velocity. Each application contains a `job_id`. You need to enrich every application with the current `job_title_short`, `salary_year_avg`, and `job_work_from_home` status from `job_postings_fact`. The job postings table is updated once daily and has ~500K rows.

**Solution:**

```sql
-- 1. Create a broadcast stream from the dimension table (run periodically, e.g., daily)
CREATE TABLE job_postings_broadcast AS
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE;

-- 2. In your streaming job (pseudocode using Flink SQL patterns)
SELECT 
  a.application_id,
  a.job_id,
  a.application_timestamp,
  b.job_title_short,
  b.salary_year_avg,
  b.job_work_from_home
FROM applications_stream a
LEFT JOIN job_postings_broadcast FOR SYSTEM_TIME AS OF a.application_timestamp AS b
  ON a.job_id = b.job_id;

-- 3. Each worker receives the full broadcast table in local state
--    Lookups are O(1) memory-resident; no remote DB calls per event
```

## Notes

- **Memory vs. latency trade-off:** Broadcast works only if your reference data fits comfortably in task memory; profile before deploying at scale.
- **Stale data risk:** Broadcasts update on a schedule; applications enriched between broadcasts get outdated values. Document your acceptable staleness window.
- **Adjacent pattern—keyed streams:** If reference data is too large or changes too fast, use a keyed stream join where both sides are partitioned by key and state is externally managed.
- **Version control for broadcasts:** Treat broadcast snapshots as versioned artifacts; timestamp them and consider versioning in your enrichment logic so you can replay or debug.
- **Revisit: changelog streams vs. snapshots:** Broadcast snapshots are simpler but lossy; changelog streams (insert/update/delete events) allow you to track evolution—useful for audit and late-arriving corrections.
