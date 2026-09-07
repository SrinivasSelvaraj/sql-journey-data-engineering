---
date: 2026-09-07
phase: streaming
topic: Late data handling: allowed lateness and window triggers
---

# Late data handling: allowed lateness and window triggers

*Streaming and distributed processing*

## Concept

Late data is information that arrives after the window it logically belongs to has already closed and been emitted. In streaming systems, you cannot wait forever for stragglers—you must decide: when to stop accepting late records, and when to trigger output. *Allowed lateness* sets a grace period (e.g., "accept records up to 2 hours after their event time"), while *window triggers* control *when* results are emitted (on-time, on late data, on every record, or periodically). Without these mechanisms, you either discard valuable late-arriving data or hold windows open indefinitely, blocking downstream consumers and consuming memory.

This matters acutely when data sources are unreliable, network-delayed, or distributed across regions—common in production. A job application arriving 90 minutes late due to a mobile app queue should still count toward the correct day's hiring pipeline. But if you accept *all* late data indefinitely, your window never truly closes, and aggregations remain in flux forever, breaking the contract that a consumer has a final answer.

## Practice

**Problem:** You ingest job postings from multiple regions. A posting's event time is `job_posted_date`. Some postings arrive 3+ hours late due to regional network delays. You want a daily aggregate of average salary by job title, emitted once per day, but you also want to incorporate late data that arrives within 4 hours of the day's close.

```sql
-- Pseudocode for Apache Flink / Beam logic
SELECT
  TUMBLE_START(job_posted_date, INTERVAL '1' DAY) AS posting_day,
  job_title_short,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary,
  COUNT(*) AS posting_count
FROM job_postings_fact
GROUP BY
  TUMBLE(job_posted_date, INTERVAL '1' DAY'),
  job_title_short
-- Emit on-time result at end of day, then re-emit if late data arrives
EMIT STRATEGY: ON_WATERMARK, ON_TIME_AND_LATE
-- Late data accepted up to 4 hours after watermark
ALLOWED_LATENESS: INTERVAL '4' HOUR
```

**What this does:** Each calendar day is a tumbling window. At midnight (watermark), results emit once. If a posting with `job_posted_date` = yesterday arrives within 4 hours after midnight, the aggregate re-emits with the new record included. After 4 hours, that window closes permanently; any later records are sidelined to a dead-letter or logged separately.

## Notes

- **Confusing allowed lateness with window duration:** Allowed lateness *extends* a window's lifetime for stragglers; it does not change the window size itself. A 1-day window is still 1 day; lateness just adds a grace period.
- **Watermarks are assumptions, not guarantees:** The watermark estimates progress through event time, but it can stall if a source slows down. Late data may arrive even after watermark advances; lateness thresholds hedge this uncertainty.
- **State memory trade-off:** Longer allowed lateness = holding more intermediate state (buckets, partial aggregates) in memory. Monitor state size in production; set lateness based on SLA, not just optimism.
- **Idempotence and merging:** If a trigger fires multiple times (one on-time, one late), your downstream consumer must either deduplicate by window key or support retractions. Exactly-once semantics require careful handling.
- **Related:** Watermark strategies, windowing functions, side outputs (for sidelined late data), and session windows (which extend dynamically based on gaps in data rather than clock time).
