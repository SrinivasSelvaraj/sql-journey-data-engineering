---
date: 2026-10-19
phase: streaming
topic: Flink keyed state: per-key aggregation across parallel tasks
---

# Flink keyed state: per-key aggregation across parallel tasks

*Streaming and distributed processing*

## Concept

Flink keyed state maintains separate state for each distinct key in a stream, enabling per-key aggregation across parallel tasks without data loss or inconsistency. When a record arrives, Flink routes it to the task handling that key's state, ensuring all records with the same key reach the same state instance. This is essential because parallelism means multiple tasks process data simultaneously—without keyed state, you'd lose track of aggregations or produce incorrect results when a task crashes and recovers.

Keyed state matters most when you need to compute running metrics (moving averages, counts, sums) grouped by dimension—job location, job title, employer—over unbounded streams. Without it, you either lose intermediate results on task failure, double-count records on recovery, or incorrectly merge partial aggregates from different parallel tasks. Flink's state backend (RocksDB, in-memory, or external stores) persists state and restores it during recovery, ensuring exactly-once semantics.

The key insight: keyed state is local to a key's assigned task and survives failures because it's checkpointed. Queries like "running average salary by job location" become feasible because each location's state (sum, count, timestamp) is recoverable and isolated from other locations.

## Practice

**Problem:** Compute a 1-hour tumbling window of average salary per job location, handling late-arriving records and task failures. You need to emit the average whenever a window closes, even if some records arrive after the window end.

```sql
SELECT 
  TUMBLE_START(job_posted_date, INTERVAL '1' HOUR) AS window_start,
  TUMBLE_END(job_posted_date, INTERVAL '1' HOUR) AS window_end,
  job_location,
  AVG(salary_year_avg) AS avg_salary_per_location,
  COUNT(*) AS job_count
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
  AND job_location IS NOT NULL
GROUP BY 
  TUMBLE(job_posted_date, INTERVAL '1' HOUR),
  job_location;
```

Flink's keyed state groups records by `(job_location, window_id)` and maintains running sum and count per key. On task failure, the state is restored from the checkpoint, and late records within the allowed lateness window update the correct location's aggregate without duplication.

## Notes

- **Mistake:** Assuming keyed state is free; large state (millions of keys with heavy objects) causes memory pressure and slow RocksDB compactions. Profile state size and evict stale keys with TTL.
- **Adjacent topic:** *State backends* (in-memory, RocksDB, external)—choose based on state size and latency tolerance; RocksDB scales beyond heap but adds I/O overhead.
- **Adjacent topic:** *Watermarks and allowed lateness*—keyed state without watermark handling cannot distinguish between late records and out-of-order ones; configure `allowedLateness()` to extend the window retention window.
- **Worth revisiting:** *Queryable state* lets external systems read Flink's state directly, enabling dashboards that reflect true in-flight aggregates without a separate database.
- **Common trap:** Forgetting to set a *state TTL*; unbounded key cardinality (unique job IDs instead of locations) bloats state forever, eventually crashing the job.
