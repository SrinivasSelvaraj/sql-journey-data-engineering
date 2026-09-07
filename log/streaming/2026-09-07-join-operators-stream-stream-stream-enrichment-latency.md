---
date: 2026-09-07
phase: streaming
topic: Join operators: stream-stream, stream-enrichment latency
---

# Join operators: stream-stream, stream-enrichment latency

*Streaming and distributed processing*

## Concept

Stream-stream joins combine two continuous data streams based on a join key, holding state in memory or persistent stores to match events that arrive at different times. Unlike batch joins where both sides are complete, streaming joins must decide: *how long do I wait for the matching event from the other stream?* This decision is captured by the join window—a time interval during which the operator buffers events looking for matches. Without a window bound, the state grows unbounded and memory explodes; set it too tight and late-arriving events are silently dropped, creating silent data loss that's hard to detect.

Stream-enrichment joins are a special case where one stream (fast, high-volume) is joined against a slower reference stream or lookup table. The latency cost is the delay between when an enrichment fact becomes available and when it can be applied to join with the main stream. This matters acutely in fraud detection, recommendations, or pricing: if your enrichment data is 5 seconds stale but your join window is 2 seconds, you silently miss applying the latest context. The operator must balance **state size** (how much history to keep), **correctness** (not dropping valid matches), and **latency** (how fresh the enrichment is).

## Practice

**Problem:** You have two streams: `job_postings` (real-time new postings) and `salary_updates` (periodic corrections to salary data for existing jobs). You need to join them so that each posting is enriched with the most recent salary within 10 minutes of the posting time. A job posted at 14:00 should only match salary updates arrived between 13:50 and 14:10.

```sql
-- Using a time-windowed stream-stream join (Flink-style pseudocode)
SELECT 
  j.job_id,
  j.job_title_short,
  COALESCE(s.salary_year_avg, j.salary_year_avg) AS final_salary,
  j.job_work_from_home,
  j.job_posted_date,
  j.job_location,
  s.salary_update_time
FROM job_postings j
INNER JOIN salary_updates s
  ON j.job_id = s.job_id
  AND s.salary_update_time BETWEEN j.job_posted_date - INTERVAL '10 MINUTE' 
                                AND j.job_posted_date + INTERVAL '10 MINUTE'
WHERE j.job_posted_date >= NOW() - INTERVAL '1 HOUR';
-- Window retention: keep job_postings state for 10 min, salary_updates for 10 min
-- Late arrivals beyond window are dropped; consider a separate side-output for them
```

## Notes

- **Unbounded state is the silent killer:** without explicit window bounds, join state grows with every event and the job eventually runs out of memory. Always define your join time window based on business SLAs, not hope.
- **Late-arrival semantics vary:** Kafka Streams drops by default; Flink has allowed lateness; know your framework's behavior or you'll lose data without knowing.
- **Enrichment latency compounds:** if enrichment table updates take 30 seconds to propagate and your join window is 5 seconds, you're applying stale enrichment. Measure end-to-end latency, not just join latency.
- **State backends matter:** in-memory joins are fast but risky (lose state on failure); persistent backends (RocksDB, DynamoDB) add latency but survive restarts. Choose based on recovery requirements.
- **Connects to:** stateful processing, watermarks and event time, backpressure, exactly-once semantics, and side outputs for error handling.
