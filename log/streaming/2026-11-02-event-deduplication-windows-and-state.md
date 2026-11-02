---
date: 2026-11-02
phase: streaming
topic: Event deduplication windows and state
---

# Event deduplication windows and state

*Streaming and distributed processing*

## Concept

Event deduplication windows define the time period during which a streaming system tracks seen events to filter out duplicates. In a distributed, out-of-order world, the same event (same user action, transaction, or record) often arrives multiple times—from retries, network failures, or replayed logs—and must be recognized and suppressed. Without deduplication state, you count the same purchase twice, fire the same alert multiple times, or corrupt aggregate metrics.

The state required to deduplicate is typically a set of event identifiers (keys) plus a watermark indicating how old an event can be before it is no longer deduplicated. Once an event's timestamp falls outside the deduplication window, the system forgets it and will accept a duplicate. This forces a trade-off: a long window consumes memory and slows queries; a short window risks accepting late duplicates that arrive after the window closes.

Deduplication is essential in any system ingesting events from multiple sources, reshuffling data, or replaying logs. Without it, your metrics drift, reconciliation fails, and downstream joins produce inflated row counts.

## Practice

**Problem:** Job postings stream into your system from multiple job boards. The same posting (identified by `job_id`) often arrives twice within seconds due to API retries or dual-source ingestion. You need to deduplicate within a 5-minute window and emit only the first occurrence of each job posting.

```sql
WITH deduplicated AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY job_id 
      ORDER BY job_posted_date ASC
    ) AS rn
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_TIMESTAMP - INTERVAL '5 minutes'
)
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM deduplicated
WHERE rn = 1;
```

## Notes

- **State explosion:** Deduplication state grows with event cardinality and window size. At high volume, consider bucketing by source or partitioning by date to avoid memory bloat.
- **Late arrivals vs. duplicates:** A record arriving 10 minutes late looks identical to a duplicate; the deduplication window is your only defense. Set it conservatively for high-risk pipelines.
- **Exactly-once delivery:** Deduplication is a *consumer-side* guarantee. It does not replace idempotent producers; both are needed for truly reliable systems.
- **Watermarking and allowed lateness:** Deduplication windows are tightly coupled to stream time tracking (event time vs. processing time) and the watermark that signals "no more events before this timestamp will arrive."
- **Adjacent patterns:** Bloom filters offer probabilistic deduplication with lower memory; distinct counts and HyperLogLog approximate unique events; changelogs and CDC logs require deduplication of schema-change events.
