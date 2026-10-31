---
date: 2026-10-31
phase: streaming
topic: Late arriving data and session window closure
---

# Late arriving data and session window closure

*Streaming and distributed processing*

## Concept

Late arriving data occurs when records arrive after the session window they belong to has already closed and been emitted. In streaming systems, you must decide: do you ignore the late record, re-emit the window, or hold state longer? Without a strategy, you silently lose data or emit conflicting results downstream.

Session windows are particularly vulnerable because they close on inactivity—a user's next action arriving 10 minutes late can't be grouped with the original session. This matters for user behavior analysis, fraud detection, and billing: a purchase 5 minutes after session close should either extend the session, trigger a late update, or be flagged as out-of-band.

The cost of ignoring late data is silent incompleteness. The cost of accepting all late data is unbounded state retention and cascading recalculations. Real systems use grace periods (a buffer after window close) and emit update modes (early, on-time, late) to balance correctness and resource efficiency.

## Practice

**Problem:** You ingest job application events with a timestamp and user_id. You want to build a session window (30 minutes of inactivity) for each user to count applications per session, but applications occasionally arrive 2–5 minutes late due to API delays. How do you count applications accurately without holding unbounded state?

```sql
-- Using Flink or Spark Structured Streaming syntax
-- Apply watermarking + session window + allowedLateness

SELECT 
  user_id,
  TUMBLE_START(event_time, INTERVAL '30' MINUTE) AS session_start,
  TUMBLE_END(event_time, INTERVAL '30' MINUTE) AS session_end,
  COUNT(DISTINCT job_id) AS applications_per_session,
  MAX(CURRENT_TIMESTAMP) AS result_emit_time
FROM job_applications
WHERE event_time > CURRENT_TIMESTAMP - INTERVAL '2' HOUR
GROUP BY 
  user_id,
  TUMBLE(event_time, INTERVAL '30' MINUTE)
;

-- More explicit: Session window with grace period (Flink)
-- SELECT user_id, COUNT(*) 
-- FROM job_applications
-- GROUP BY user_id, SESSION(event_time, INTERVAL '30' MINUTE)
-- WITH (allowed_lateness = INTERVAL '5' MINUTE)
```

The solution uses a watermark (implicit or explicit) to wait 5 minutes past the session close before emitting final results, allowing stragglers to be included. Events beyond the grace period are either dropped or routed to a separate "late" stream.

## Notes

- **Watermarking vs. grace periods:** Watermarks signal progress through time; grace periods define how long after window close to keep state. Both needed for correctness.
- **State explosion risk:** Session windows + long grace periods = large in-memory maps. Tune based on SLA and late arrival frequency, not hope.
- **Emit modes matter:** Early (preliminary), on-time (after grace closes), late (stragglers)—downstream must handle contradictions or idempotency becomes critical.
- **Exactly-once illusion:** Late data with grace periods requires retracting old results and re-emitting; this only works if your sink supports updates/retractions or computes idempotently (sum, count, set union—not order-dependent operations).
- **Adjacent: event time vs. processing time**, out-of-order handling, idempotent writes, schema evolution (late data may be old schema versions).
