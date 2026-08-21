---
date: 2026-08-21
phase: modelling
topic: Snapshot tables vs transactional tables for audit
---

# Snapshot tables vs transactional tables for audit

*Data modelling and warehousing*

## Concept

A **snapshot table** captures a complete state of data at a point in time, while a **transactional table** records individual events or changes. For audit purposes, snapshots let you answer "what did this entity look like on date X?" without reconstructing history from logs. Transactional tables answer "what changed and when?" but require aggregation to see state.

This distinction matters when you need to comply with audit requirements, calculate metrics as-of dates, or explain business decisions. Without snapshots, you either lose history (if you only keep current state) or force every analyst to write complex window functions and join logic to reconstruct what was true at a specific moment. Snapshots trade storage for query simplicity and correctness.

For job postings, a transactional table might record salary adjustments or location changes as separate rows. A snapshot table would store one row per job per day, capturing the full posted state on that date—so you can query "what jobs were remote in March?" without ambiguity about when a field changed.

## Practice

**Problem:** You need to audit which job postings were actively offering a salary above $150k on 2025-01-15. Your `job_postings_fact` table updates in place, so you've lost the historical salary values. How do you answer this question reliably without recreating history?

**Solution:** Create a daily snapshot table and query it instead.

```sql
-- Create snapshot table (load daily via scheduled pipeline)
CREATE TABLE job_postings_snapshot (
    snapshot_date DATE,
    job_id INT,
    job_title_short VARCHAR,
    salary_year_avg INT,
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    job_location VARCHAR,
    PRIMARY KEY (snapshot_date, job_id)
);

-- Audit query: jobs with $150k+ salary on audit date
SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_location
FROM job_postings_snapshot
WHERE snapshot_date = '2025-01-15'
  AND salary_year_avg > 150000
  AND job_posted_date <= snapshot_date
ORDER BY salary_year_avg DESC;
```

## Notes

- **Snapshot vs. SCD Type 2:** Snapshots store full state per time period; SCD Type 2 adds `effective_date` and `end_date` columns to transactional records. Snapshots are simpler for audits but costlier to store; SCD Type 2 saves space but requires more complex queries.

- **Storage cost trap:** Daily snapshots of large tables compound quickly. Consider weekly or monthly snapshots for less volatile dimensions, or use change data capture (CDC) logs + transactional tables for audit trails, then materialize snapshots only for key dates.

- **Grain confusion:** Document whether your snapshot is "state at end of day" or "state at start of day"—this matters for time-sensitive queries and prevents off-by-one errors in compliance reporting.

- **Reconstruction fallback:** If you inherit a table without historical snapshots, you can sometimes reconstruct audit state from event logs, database transaction logs, or change-tracking columns (`dbt_updated_at`), but this is fragile. Build snapshots from day one.

- **Adjacent concept—Audit tables:** Separate, immutable audit logs (insert-only, never update/delete) complement snapshots for proving *why* something changed, while snapshots show *what* changed.
