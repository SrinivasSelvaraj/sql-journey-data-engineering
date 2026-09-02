---
date: 2026-09-02
phase: pipelines
topic: Replay and time travel: reprocessing from checkpoint
---

# Replay and time travel: reprocessing from checkpoint

*Pipelines and orchestration*

## Concept

Replay and time travel enable you to reprocess historical data from a known good state (checkpoint) without losing intermediate results or corrupting your warehouse. Instead of rerunning an entire pipeline from scratch, you save state—usually as a committed version of a table or a marked point in your processing log—and resume from there when logic changes, bugs are discovered, or late-arriving data arrives.

This matters most when pipelines are expensive (full table scans cost money and time), when data arrives out-of-order, or when you need to fix a calculation bug without recomputing months of prior work. Without checkpoints, a single bad transformation forces you to either accept corrupted data downstream or waste compute redoing everything. With them, you trade storage (keeping intermediate states) for safety and speed.

The key distinction: replay means re-running logic on the same input data from a checkpoint; time travel means querying *what the table looked like* at a prior point. Both require immutable snapshots or versioned state. Most modern data lakes (Iceberg, Delta) support this via transaction logs and file-level versioning.

## Practice

**Problem:** Job posting salaries are recalculated weekly based on new market data, but a formula bug in week 3 doubled all salaries. You've now processed through week 8. Rather than recompute weeks 1–8 from raw source data, replay the corrected logic from week 2's checkpoint.

```sql
-- Checkpoint at end of week 2: save a clean version
CREATE TABLE job_postings_fact_week2_checkpoint AS
SELECT * FROM job_postings_fact
WHERE job_posted_date < '2024-01-21';

-- Week 3 runs with bug, weeks 4–8 propagate it
-- Fix: replay weeks 3–8 from checkpoint, then union clean earlier weeks
WITH corrected_week3_onward AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg / 2 AS salary_year_avg,  -- undo the bug
    job_work_from_home,
    job_posted_date,
    job_location
  FROM raw_job_postings
  WHERE job_posted_date >= '2024-01-21'
    AND job_posted_date < '2024-02-25'
)
SELECT * FROM job_postings_fact_week2_checkpoint
UNION ALL
SELECT * FROM corrected_week3_onward;
```

## Notes

- **Checkpoint granularity matters:** daily checkpoints are safer but costlier to store than weekly ones; balance frequency against your SLA for max acceptable data loss.
- **Delta Lake and Iceberg excel here:** both maintain transaction logs that let you query `AS OF VERSION` or `AS OF TIMESTAMP`, making replay queries simpler than manual snapshots.
- **Confuse replay with idempotency at your peril:** idempotent operations can run twice safely; replay is about *intentionally* re-running with corrected logic. Document which is which in your DAG.
- **Late-arriving facts (slowly changing dimensions):** if job salary data updates retroactively after posting, your checkpoint strategy must decide whether to merge late arrivals or treat them as a separate stream—affects replay logic.
- **Adjacent:** SCD Type 2 (slowly changing dimensions), state machine patterns in orchestration, and audit logs; all require versioned or immutable storage.
