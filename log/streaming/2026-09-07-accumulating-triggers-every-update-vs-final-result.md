---
date: 2026-09-07
phase: streaming
topic: Accumulating triggers: every update vs final result
---

# Accumulating triggers: every update vs final result

*Streaming and distributed processing*

## Concept

**Accumulating triggers** determine whether a streaming aggregation or window function emits output *every time* an update arrives (every-update mode) or *only when the window closes* (final result mode). This distinction is critical in distributed systems because out-of-order data, late arrivals, and partial state changes can cause cascading recalculations downstream.

In every-update mode, each arriving record triggers a new output—useful for real-time dashboards but expensive and potentially incorrect if consumers expect immutable facts. In final result mode, outputs are emitted only when a window boundary is crossed (e.g., end of hour), reducing downstream churn but risking stale metrics if you need immediate visibility. The choice propagates: a carelessly chosen trigger can force buffering, retractions, or duplicate processing in all dependent pipelines.

Without explicit trigger reasoning, systems default to one behavior (often every-update), masking the actual semantics. This breaks reconciliation: batch and stream results diverge because batch naturally produces "final" results while streams leak intermediate ones. The cost appears as duplicate deduplication logic, correctness bugs in joins, and confusion about which metric is authoritative.

## Practice

**Problem:** You track job posting removals in a fact table. Every time a job is updated (salary changed, location edited), you emit it immediately. By end-of-day, 50 different downstream reports re-aggregate the same job 50 times. How do you emit only the final snapshot per job per day?

```sql
-- Every-update (problematic): emits on each salary_year_avg change
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  CURRENT_TIMESTAMP AS processed_at
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE;

-- Final result (correct): collect all updates, emit once per day boundary
SELECT
  job_id,
  job_title_short,
  MAX(salary_year_avg) AS final_salary_year_avg,
  job_location,
  CURRENT_DATE AS snapshot_date
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE
GROUP BY job_id, job_title_short, job_location, CURRENT_DATE
HAVING COUNT(*) > 0;  -- Triggers only at window close (end of day)
```

## Notes

- **Confusion between `EMIT_ON_UPDATE` vs `EMIT_ON_WINDOW_CLOSE`**: Many engines (Flink, Spark Structured Streaming) default to emitting on every microbatch; you must explicitly configure `OutputMode.Complete` or `OutputMode.Final` to suppress intermediate states.
- **Retractions and corrections**: Every-update mode requires receivers to handle retractions (retract old value, insert new one). Final result mode avoids this but introduces latency—pick based on your SLA and downstream tolerance.
- **Watermarks and allowed lateness**: Accumulating triggers interact with watermark strategy; a late arrival after the window has closed triggers a retraction in every-update mode but is often ignored in final mode (or merged in a separate "correction" batch).
- **Idempotency and deduplication**: If a trigger misfires and emits twice, idempotent sinks (keyed writes, upserts) matter more in every-update mode; final result mode is naturally more forgiving because results are stable by definition.
- **Reconciliation patterns**: Always run a separate batch "ground truth" job at day-end to compare against streaming aggregates. The batch naturally computes final results; if it differs from stream, your trigger choice was wrong or your watermark logic is leaking records.
