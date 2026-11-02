---
date: 2026-11-02
phase: streaming
topic: Streaming aggregation memory requirements
---

# Streaming aggregation memory requirements

*Streaming and distributed processing*

## Concept

Streaming aggregation memory requirements arise when computing running aggregates (counts, sums, averages, distinct values) over unbounded data streams. Unlike batch processing where you load finite data into memory, streaming systems must maintain state—intermediate results for partially-completed windows or groups—indefinitely or until windows close. This state grows linearly with cardinality: aggregating by job_location across millions of posts means storing partial results for every unique location in memory simultaneously.

Memory becomes critical when cardinality is high, windows are long, or late-arriving data extends state lifetime. A 24-hour tumbling window aggregating by job_id requires holding all 24 hours of data in memory until the window closes. If your stream has 100K unique job_ids, you're holding 100K state objects. Without memory management, systems either crash (hitting limits), evict state prematurely (losing correctness), or slow catastrophically as garbage collection pauses lengthen.

The solution is designing aggregations with bounded cardinality, early cutoff semantics (watermarks), and state time-to-live (TTL). You must reason about: _How many unique keys will coexist in state?_ _How long do I need to wait for late data?_ _What's my memory budget per key?_

## Practice

**Problem:** You need to compute average salary by job_title_short every 1 hour from a continuous stream of job postings. Late arrivals (postings timestamped up to 2 hours in the past) should be included. You expect ~500 unique job titles and 50K postings/hour. What memory would you budget, and how would you configure the aggregation?

```sql
-- Kafka/Flink-style pseudocode (SQL window function)
SELECT 
  TUMBLE_START(job_posted_date, INTERVAL '1' HOUR) AS window_start,
  job_title_short,
  AVG(salary_year_avg) AS avg_salary,
  COUNT(*) AS posting_count
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY 
  TUMBLE(job_posted_date, INTERVAL '1' HOUR),
  job_title_short
EMIT AFTER WATERMARK  -- Only emit when watermark passes window_end
;

-- Configuration (Flink example):
-- Window: 1 hour tumbling, 2-hour allowed lateness
-- State TTL: 3 hours (window + lateness buffer)
-- Expected state size: 500 titles × 3 hours of partial aggregates × ~1KB per state ≈ 1.5 MB
-- Memory: 50K postings/hour ÷ 500 titles = 100 postings/title/hour → manageable
```

## Notes

- **Common mistake:** Not setting state TTL and letting late-data windows accumulate forever; always configure explicit cleanup windows based on your allowed-lateness SLA.
- **Cardinality explosion:** Avoid grouping by high-cardinality fields (user_id, job_id) at the streaming layer; use session windows or pre-filter to known sets (e.g., top 100 titles only).
- **Watermarking is essential:** Without watermarks, the system doesn't know when a window is truly complete; you either emit incomplete results early or hold state indefinitely waiting for stragglers.
- **Adjacent: State backend strategy** — RocksDB (embedded) vs. external store (Redis) affects memory vs. latency tradeoffs; for 1–2 GB state, embedded is fine; beyond that, consider externalization.
- **Revisit:** Joins in streaming (state explodes multiplicatively) and exactly-once semantics (state checkpointing costs) both amplify memory pressure.
