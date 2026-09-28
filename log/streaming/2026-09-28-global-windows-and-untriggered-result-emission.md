---
date: 2026-09-28
phase: streaming
topic: Global windows and untriggered result emission
---

# Global windows and untriggered result emission

*Streaming and distributed processing*

## Concept

A **global window** is a single, unbounded window that contains all data across all time—there is no automatic window boundary to trigger result emission. In streaming systems like Apache Beam or Flink, this is useful when you want to compute aggregates over an entire dataset without time-based partitioning (e.g., running totals, global rank, all-time statistics). However, without an explicit trigger, a global window will never close on its own, so you must define *when* results should be emitted: after N records, after a timeout, when a custom condition is met, or on element arrival. Without a trigger strategy, your pipeline will buffer data indefinitely and never produce output, making global windows silent failure points in streaming jobs.

The key tension is between *completeness* and *latency*. A global window guarantees you see all historical data, but it also means results cannot be final until the stream ends (which it may never do). Triggers let you emit partial, incremental results; the cost is handling late-arriving data and potentially retracting or updating earlier outputs. This is why global windows are less common than time-based windows in real-time systems—they require explicit thinking about when "done" actually means.

## Practice

**Problem:** You want to track the total salary budget and job count for all remote-work postings across your entire job_postings_fact table as a streaming feed arrives. You need results every 100 new remote jobs posted, but you also want a safety valve that emits after 30 seconds of silence, whichever comes first.

```sql
-- Pseudocode for Beam or Flink-style approach (not standard SQL)
-- In a real system, this would be Python/Java SDK code, but the concept:

SELECT
  COUNT(*) as total_remote_jobs,
  SUM(salary_year_avg) as total_salary_budget,
  AVG(salary_year_avg) as avg_salary,
  CURRENT_TIMESTAMP as result_timestamp
FROM job_postings_fact
WHERE job_work_from_home = TRUE
-- Applied to GLOBAL window with dual trigger:
--   1. COUNT-BASED: emit after 100 new remote postings
--   2. TIME-BASED: emit after 30 seconds of no new data
-- Both triggers fire independently; earliest wins in this case
```

In Beam/Flink code, this becomes:
- `.apply(Window.into(GlobalWindows()))`
- `.apply(Trigger.of(AfterPane.elementCountAtLeast(100)).orFinally(AfterProcessingTime.pastFirstElementInPane(Duration.standardSeconds(30))))`
- `.apply(ParDo.of(aggregate_and_emit_fn))`

## Notes

- **Trigger cardinality trap:** Every trigger fire emits a *pane* (a result shard). Without accumulating mode set carefully, you may emit overlapping or contradictory results; always clarify: are results cumulative, delta-only, or replacing?

- **Retractions and late data:** Global windows don't know what "late" means—if data arrives out of order, you must either retract old results or accept that global aggregates may change retroactively. This is adjacent to the Lambda Architecture pattern (batch + speed layers).

- **Memory and state management:** A true global window with no trigger will grow the in-memory state forever. Even with triggers, unbounded state can crash workers; consider using external state stores (Redis, Firestore) for very large windows.

- **When to avoid global windows:** Time-windowed analytics (session windows, tumbling windows) are usually better for real-time dashboards and alerting. Global windows shine for one-off batch-like computations embedded in streaming pipelines.

- **Testing gotcha:** Unit tests often don't fire triggers automatically—you must manually advance processing time or inject trigger-fire events to see output; otherwise your test silently hangs.
