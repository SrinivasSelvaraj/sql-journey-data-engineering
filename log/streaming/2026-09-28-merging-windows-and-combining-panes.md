---
date: 2026-09-28
phase: streaming
topic: Merging windows and combining panes
---

# Merging windows and combining panes

*Streaming and distributed processing*

## Concept

Merging windows and combining panes address the fundamental challenge of producing meaningful results from unbounded, out-of-order data streams. A window groups events by time (tumbling, sliding, session-based), and a pane represents the output state at a given trigger point—early results before the window closes, on-time results when the watermark passes the window end, or late results after closure. Without merging and combining logic, you either lose late-arriving data entirely or emit duplicate/contradictory aggregates that confuse downstream systems.

The practical cost of ignoring this: imagine counting daily job postings. If a posting arrives 3 days late due to network delay, a simple windowed query might assign it to the wrong day or drop it. Combining panes lets you emit an initial count, then refine it as late data arrives—critical for dashboards and SLAs that need both timeliness and correctness. Merging windows (in frameworks like Beam or Flink) ensures that when panes fire multiple times, their aggregations compose correctly: a sum of partial sums must equal the final sum.

## Practice

**Problem:** Calculate the average salary for remote jobs posted each day, emitting early estimates and refining them as late data arrives within a 24-hour grace period.

```sql
SELECT
  TUMBLE_START(job_posted_date, INTERVAL '1' DAY) AS window_start,
  TUMBLE_END(job_posted_date, INTERVAL '1' DAY) AS window_end,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary,
  COUNT(*) AS job_count,
  CURRENT_TIMESTAMP AS pane_fired_at
FROM job_postings_fact
WHERE job_work_from_home = TRUE
GROUP BY TUMBLE(job_posted_date, INTERVAL '1' DAY)
EMIT CHANGES;
```

Pair this with a trigger strategy in your streaming engine (Flink/Beam): fire on every element for early panes, fire at window end for on-time, and fire within 24 hours for late panes. Downstream, deduplicate by `(window_start, pane_fired_at)` and always use the latest pane.

## Notes

- **Merging ≠ deduplicating:** Merging combines partial aggregates (e.g., sum of two sums); deduplication removes duplicate rows. Both often happen in the same pipeline but solve different problems.
- **Watermarks are assumptions:** A watermark says "no data earlier than T will arrive," but networks and out-of-order ingestion violate this. Grace periods (late-data windows) trade latency for correctness recovery.
- **State explosion risk:** Keeping pane history indefinitely for late-arriving jobs bloats state storage. Set explicit grace periods (e.g., 24 hours) and purge older panes to avoid runaway memory use.
- **Idempotent sinks matter:** If a downstream system receives the same pane twice, it must not double-count. Use idempotent writes (upsert by primary key) or transaction IDs.
- **Connects to:** watermarks, allowed lateness, stateful processing, session windows (which merge based on inactivity, not clock time).
