---
date: 2026-09-05
phase: streaming
topic: Flink stateful functions and keyed state
---

# Flink stateful functions and keyed state

*Streaming and distributed processing*

## Concept

Keyed state in Flink allows a stateful operator to maintain separate state for each unique key, enabling you to aggregate, deduplicate, or correlate events belonging to the same entity across time. When a record arrives, Flink routes it to a task instance based on its key, ensuring all events for that key (e.g., all job postings from a specific location, or all events for a specific user) are processed by the same parallel instance. This guarantees consistent, ordered processing within each key partition.

Without keyed state, you cannot answer questions like "what is the running average salary for remote jobs posted in the last 7 days?" or "has this job location already posted 10+ similar positions today?" Each arriving event would be processed in isolation, with no memory of previous events. You'd lose the ability to detect patterns, maintain counters, or build incremental aggregations—critical for fraud detection, windowed analytics, and session tracking.

The key challenge is that state must be fault-tolerant: if a task fails, its state must be recovered from a checkpoint. Flink handles this via distributed snapshots, but you must design your state thoughtfully to avoid bottlenecks (e.g., don't key by job_title if it has too many distinct values) and manage state lifecycle (TTL, explicit cleanup) to prevent unbounded memory growth.

## Practice

**Problem:** Track the maximum salary posted per job location in the last 24 hours, updating a result table each time a new posting arrives. You need to know: for each location, what was the highest salary we've seen today?

```sql
-- Keyed state approach: key by job_location, maintain max salary
-- In Flink SQL/DataStream API

SELECT 
  job_location,
  MAX(salary_year_avg) AS max_salary_today,
  TUMBLE_END(job_posted_date, INTERVAL '1' DAY) AS day_end
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE
GROUP BY 
  job_location,
  TUMBLE(job_posted_date, INTERVAL '1' DAY)
;

-- Or with Flink DataStream API (pseudocode):
-- stream
//   .keyBy(record => record.job_location)  // Partition by location
//   .flatMap(new MaxSalaryAggregator())      // Maintain max in keyed state
//   .print()
```

The state operator maintains one `ValueState<Double> maxSalary` per unique job_location key. As each posting arrives, it checks the current max and updates if needed—all without reshuffling past data.

## Notes

- **Common mistake:** Keying by high-cardinality fields (e.g., job_id) creates too many state partitions and kills parallelism; key by entities with bounded cardinality (location, job_title_short).
- **State lifecycle:** Always set a TTL (time-to-live) on state—otherwise, state for old keys (locations that posted long ago) accumulates forever, consuming memory.
- **Connects to:** Windowing (tumbling, sliding, session) defines *when* state is emitted and cleared; watermarks control when late data is rejected; savepoints enable exactly-once semantics.
- **Keyed vs. operator state:** Keyed state is partitioned by key and scales with parallelism; operator state is local to a task and useful for singleton aggregations (total job count across all locations).
- **Revisit:** Investigate RocksDB backend for large state volumes and rescaling strategies (key distribution changes when parallelism increases).
