---
date: 2026-09-27
phase: streaming
topic: Keyed vs broadcast state in Flink jobs
---

# Keyed vs broadcast state in Flink jobs

*Streaming and distributed processing*

## Concept

**Keyed state** is scoped to a single key within a partition and maintains separate state per entity. When you apply a `keyBy()` operation in Flink, the stream is repartitioned so that all records with the same key reach the same task. Each task instance holds its own isolated state dictionary. This is essential for stateful operations like aggregations, deduplication, and windowing where you need independent computations per entity (e.g., per user, per job posting, per region).

**Broadcast state** is replicated across all parallel task instances and is read-only from the operator's perspective. You broadcast a small dataset (typically a control stream or a lookup table) so every task can access the same reference data without network reshuffling. Broadcast state is immutable during processing and is updated by a dedicated control stream; the main stream reads from it.

The distinction matters because keyed state scales with the number of distinct keys in your data, while broadcast state's size is fixed regardless of cardinality. Without proper state scoping, you either waste memory (broadcasting large datasets) or lose correctness (sharing mutable state across partitions without synchronization). Unordered and late-arriving data make this critical: keyed state ensures late events for a given key still reach the correct task; broadcast state ensures all tasks have consistent reference data when processing those late events.

## Practice

**Problem:** You're processing a stream of job postings and need to flag any posting where the salary is below a dynamically updated minimum threshold per job category (broadcast), while also tracking the 30-day count of postings per location (keyed state).

```sql
-- Pseudocode approximating the Flink job structure

-- Broadcast stream: category → min_salary (refreshed periodically)
SELECT job_category, min_salary_threshold, update_timestamp
FROM salary_thresholds
WHERE update_timestamp > last_broadcast_time

-- Main stream: keyed by location, broadcast joined with threshold
SELECT 
  jp.job_id,
  jp.job_title_short,
  jp.job_location,
  jp.salary_year_avg,
  threshold.min_salary_threshold,
  CASE WHEN jp.salary_year_avg < threshold.min_salary_threshold THEN 1 ELSE 0 END as below_threshold,
  COUNT(*) OVER (PARTITION BY jp.job_location ORDER BY jp.job_posted_date 
                 ROWS BETWEEN 29 DAYS PRECEDING AND CURRENT ROW) as posting_count_30d
FROM job_postings_fact jp
INNER JOIN broadcast_salary_thresholds threshold 
  ON jp.job_category = threshold.job_category
WHERE jp.job_posted_date >= CURRENT_DATE - 30
```

The keyed state (per-location counters) survives late arrivals; the broadcast state (thresholds) is consistent across all parallel instances.

## Notes

- **Keyed state memory leak:** forgetting to set a TTL (time-to-live) on keyed state leads to unbounded growth; always configure `StateTtlConfig` for long-running jobs processing high-cardinality keys.
- **Broadcast mutability trap:** broadcast state is read-only in the main operator; if you need to update it, use a separate control stream and a `BroadcastProcessFunction` to handle the lifecycle.
- **Ordering and late data:** keyed state with event-time windowing handles out-of-order events correctly because each key's state is independent; broadcast state must be updated before main-stream processing references it.
- **Connects to:** Flink's `ProcessFunction` API, event-time semantics, watermarks, and the distinction between `ValueState`, `MapState`, and `ListState` implementations.
- **Revisit:** the trade-off between state backend choices (RocksDB vs in-memory), checkpointing strategy, and how state is serialized when you scale from toy examples to production volume.
