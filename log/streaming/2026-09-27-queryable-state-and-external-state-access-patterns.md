---
date: 2026-09-27
phase: streaming
topic: Queryable state and external state access patterns
---

# Queryable state and external state access patterns

*Streaming and distributed processing*

## Concept

Queryable state is the ability to access and join against accumulated historical data (state store) while processing streaming events, without writing intermediate results back to external systems. In distributed streaming, events arrive out of order and continuously; without queryable state, you cannot enrich a real-time event with context (like whether a job posting is "hot" based on prior applications) or validate it against business rules stored in memory.

External state access patterns describe when and how to fetch data from databases, caches, or APIs during stream processing. The cost is latency and throughput: each event may trigger a remote lookup, creating bottlenecks. The risk is stale reads—if your lookup table changes between events, you may apply inconsistent rules. Without deliberate state management, you either lose context (stateless processing) or bloat your pipeline with redundant I/O.

This matters most in enrichment pipelines, fraud detection, and real-time aggregations where decisions depend on both the event and historical context. It breaks when you attempt side-channel lookups in tight loops, when state is not co-located with processing, or when you confuse queryable state (in-memory, fast) with external state (remote, slow).

## Practice

**Problem:** A streaming job must enrich job postings with the count of applications received in the last 7 days. You receive a `job_postings_fact` event and need to decide whether to flag it as "high-demand" (≥10 prior applications). State is maintained in a local state store keyed by `job_id`; external application counts are in a database.

```sql
-- Pseudocode for streaming enrichment with queryable state

-- Local state store (queryable, co-located with processor):
-- State: job_id → application_count (7-day rolling window)

-- Stream processing logic:
SELECT 
  jp.job_id,
  jp.job_title_short,
  jp.salary_year_avg,
  jp.job_posted_date,
  CASE 
    WHEN state_store.application_count >= 10 
    THEN 'high-demand' 
    ELSE 'standard' 
  END AS demand_flag
FROM job_postings_fact jp
LEFT JOIN state_store ON jp.job_id = state_store.job_id
-- Update state store after processing:
-- INSERT INTO state_store (job_id, application_count, window_end)
-- SELECT jp.job_id, COUNT(*), CURRENT_TIMESTAMP + INTERVAL 7 DAY
-- FROM applications_stream WHERE job_id = jp.job_id
```

The solution keeps the application count in a local state store (queryable without remote latency). A separate background process or windowed aggregation maintains the 7-day count from the applications stream and updates the state store; enrichment reads from state store, never calls the external database per-event.

## Notes

- **Common mistake:** Querying external databases synchronously for every event; this serializes throughput and creates cascading failures when the database is slow. Always materialize frequently-accessed state locally.
- **Stale state risk:** State stores can drift from truth if updates fail silently. Implement changelog or versioning (e.g., include timestamp in state) and periodic reconciliation.
- **Adjacent topics:** State TTL (time-to-live) for memory efficiency; dual-write consistency (keeping state store and database in sync); exactly-once semantics to prevent duplicate state updates.
- **Co-location principle:** State should be co-located with the processor instance to avoid network round-trips; partition state by join key (e.g., job_id) to match stream partitioning.
- **Revisit:** How to handle state migration and scaling; differences between embedded (RocksDB), remote (Redis), and hybrid state stores; when to use external systems as source-of-truth vs. cache.
