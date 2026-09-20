---
date: 2026-09-20
phase: pipelines
topic: Kappa architecture and log reprocessing
---

# Kappa architecture and log reprocessing

*Pipelines and orchestration*

## Concept

Kappa architecture eliminates the dual-pipeline problem (batch + stream) by treating *all* data flow as a stream. Instead of maintaining separate batch and real-time paths that diverge in logic and results, a single stream processor replays the entire event log when logic changes or bugs are discovered. The event log becomes the source of truth; recomputation is deterministic because you're running identical code over identical events.

This matters because pipelines fail. A schema change, a bug in your aggregation logic, or a corrected business rule means you need to recompute historical state. Without log reprocessing, you're stuck either rolling back production (risky) or accepting stale/incorrect data in your warehouse. Kappa makes reprocessing safe: re-run the pipeline from offset zero, write results to a new table or state store, then atomically swap. No backfill scripts. No manual SQL patches.

What breaks without it: you deploy a bug, it pollutes your fact tables for a week, and there's no clean way to fix it. You change a metric definition and can't regenerate historical values consistently. Your team argues about whether a stat is "as of when"—because batch and stream gave different answers.

## Practice

**Problem:** Job postings arrive as events (new, updated, closed). You ingest them into `job_postings_fact` daily. A bug in your salary parsing logic inflated all salaries by 10% for three days. You need to reprocess those three days' worth of events, fix the derived salary values, and ensure downstream dashboards reflect the corrected numbers.

```sql
-- Step 1: Create a staging fact table with the same schema
CREATE TABLE job_postings_fact_reprocessed AS
SELECT
  job_id,
  job_title_short,
  ROUND(salary_year_avg / 1.10, 0) AS salary_year_avg,  -- Correct the bug
  job_work_from_home,
  job_posted_date,
  job_location
FROM job_postings_staging
WHERE job_posted_date >= '2024-01-15' AND job_posted_date < '2024-01-18'
  AND job_id IN (
    SELECT DISTINCT job_id FROM job_postings_fact
    WHERE job_posted_date >= '2024-01-15' AND job_posted_date < '2024-01-18'
  );

-- Step 2: Delete the corrupted records from the production fact table
DELETE FROM job_postings_fact
WHERE job_posted_date >= '2024-01-15' AND job_posted_date < '2024-01-18';

-- Step 3: Re-insert the corrected records
INSERT INTO job_postings_fact
SELECT * FROM job_postings_staging
WHERE job_posted_date >= '2024-01-15' AND job_posted_date < '2024-01-18'
  AND salary_year_avg IS NOT NULL;  -- Apply corrected logic

-- Step 4: Validate record counts match before cleanup
SELECT COUNT(*) FROM job_postings_fact
WHERE job_posted_date >= '2024-01-15' AND job_posted_date < '2024-01-18';
```

## Notes

- **Idempotency is mandatory**: if your transformation isn't idempotent (running it twice produces the same result as running it once), reprocessing corrupts data further. Hash your events; deduplicate by (job_id, event_timestamp, operation_type).

- **Event log retention**: you can only reprocess what you've kept. Archive raw events indefinitely or at least for your SLA window (e.g., 90 days). Deleting events to save storage means you can't go back.

- **State store vs. fact table**: in true Kappa, you rebuild a changelog or state store, not a fact table. A changelog preserves history (every update); a fact table may only keep the latest. Choose based on whether you need point-in-time snapshots (dimensional slowly-changing dimension logic) or just current state.

- **Connects to**: event sourcing (where replayability is the design goal), watermarking (knowing when you're "caught up" after replay), and infrastructure patterns like Kafka + Flink or cloud-native streams (Kinesis, Pub/Sub).

- **Revisit**: test reprocessing in non-production first. Build alerts that fire if replay produces different aggregates than your previous run; that's a sign of non-determinism or a real data issue.
