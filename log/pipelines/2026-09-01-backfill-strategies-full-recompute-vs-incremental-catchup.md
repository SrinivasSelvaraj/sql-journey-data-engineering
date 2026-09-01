---
date: 2026-09-01
phase: pipelines
topic: Backfill strategies: full recompute vs incremental catchup
---

# Backfill strategies: full recompute vs incremental catchup

*Pipelines and orchestration*

## Concept

A backfill is a retroactive computation of historical data—either because a pipeline failed, a metric definition changed, or new data arrived out-of-order. **Full recompute** recalculates everything from the beginning; **incremental catchup** only processes gaps or newly available data. Full recompute is simpler, idempotent, and catches logic bugs, but costs explode on large histories. Incremental catchup is faster and cheaper but risks inconsistency if the logic drifts or if you miss edge cases around time boundaries.

The choice determines how your pipeline recovers from failure. Without a clear backfill strategy, you either re-run expensive jobs unnecessarily (wasting compute) or end up with permanently stale or partially correct data. This is especially critical in analytics and ML pipelines where stakeholders trust historical dashboards and retraining uses historical snapshots.

Most production systems use **hybrid** approaches: incremental for day-to-day operations, full recompute on schedule (weekly/monthly) or when schemas change, and targeted incremental catchup for specific failure windows. The key is making backfill a first-class citizen in your orchestration logic, not an afterthought.

## Practice

**Problem:** Your `job_postings_fact` table ingests job postings daily. On 2025-01-15, you discover that `salary_year_avg` was incorrectly nulled out for all postings between 2025-01-10 and 2025-01-14 due to a parsing bug. You've fixed the bug and the raw data is still available. You need to backfill those five days without reprocessing the entire two-year history.

```sql
-- Incremental catchup: delete and recompute only the affected window
DELETE FROM job_postings_fact
WHERE job_posted_date BETWEEN '2025-01-10' AND '2025-01-14';

INSERT INTO job_postings_fact (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT 
  jp.job_id,
  jp.job_title_short,
  CAST(jp.salary AS INTEGER) AS salary_year_avg,
  jp.work_from_home::BOOLEAN,
  jp.posted_date::DATE AS job_posted_date,
  jp.location
FROM raw_job_postings AS jp
WHERE jp.posted_date::DATE BETWEEN '2025-01-10' AND '2025-01-14'
  AND jp.salary IS NOT NULL;
```

This avoids reprocessing 2+ years of data while confidently correcting the known window.

## Notes

- **Idempotency trap:** incremental catchup assumes prior runs in the window were correct; if the bug existed longer, you'll miss it. Always validate assumptions about "what data was already processed correctly."
- **Time zone gotchas:** backfill logic often breaks across DST or timezone changes; store everything in UTC and be explicit about date boundaries in WHERE clauses.
- **State management:** orchestration tools (Airflow, dbt Cloud, Prefect) should track backfill runs separately from regular runs so you can distinguish "catchup mode" from "production mode" in monitoring.
- **Full recompute as safety valve:** schedule a monthly or weekly full recompute of key fact tables to catch accumulating logic drift; this is cheap insurance against incremental corruption.
- **Connects to:** partition pruning (separate old/new data physically), snapshot tables (immutable historical copies for audit), and idempotent transforms (DELETE + INSERT vs. UPDATE to avoid conflicts).
