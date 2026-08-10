---
date: 2026-08-10
phase: modelling
topic: Accumulating snapshot fact tables
---

# Accumulating snapshot fact tables

*Data modelling and warehousing*

## Concept

An accumulating snapshot fact table records multiple important events or milestones in a single business process lifecycle, with one row per entity and multiple date columns marking when each milestone occurred. Unlike transaction fact tables (one row per event) or periodic snapshots (one row per entity per time period), accumulating snapshots let you measure the *duration and sequence* between key stages—how long from job posting to first application, from offer to hire, or time-to-fill metrics.

This pattern matters when your business questions involve "how long did X take?" or "what's the typical path through our process?" Without it, you'd either duplicate rows across multiple snapshot tables or write complex window functions comparing transaction timestamps. Accumulating snapshots fail silently when milestone dates are missing or when you try to add a new milestone after the fact; the grain becomes ambiguous and historical queries break.

The schema works because each row is immutable once all milestones complete, so late-arriving facts (a hire date discovered weeks later) require an UPDATE or a SCD Type 2 approach. Keep the grain tight: one row per job requisition or per candidate application, not one row per company.

## Practice

**Problem:** You need to analyze hiring velocity—for each job posting, measure days from posting to first application, posting to job close, and application to hire. Your stakeholders want to filter by location and role, then see median time-to-hire by quarter.

```sql
CREATE TABLE job_postings_accumulating_snapshot (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR(100),
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_location VARCHAR(100),
  job_posted_date DATE NOT NULL,
  first_application_date DATE,
  job_closed_date DATE,
  job_filled_date DATE,
  dbt_updated_at TIMESTAMP
);

-- Query: median days-to-hire by quarter and location
SELECT
  DATE_TRUNC('quarter', j.job_posted_date) AS quarter,
  j.job_location,
  j.job_title_short,
  COUNT(*) AS postings_filled,
  PERCENTILE_CONT(0.5) WITHIN GROUP (
    ORDER BY DATE_DIFF(day, j.job_posted_date, j.job_filled_date)
  ) AS median_days_to_hire
FROM job_postings_accumulating_snapshot j
WHERE j.job_filled_date IS NOT NULL
GROUP BY 1, 2, 3
ORDER BY quarter DESC, median_days_to_hire;
```

## Notes

- **Common mistake:** Adding dimensions (like company_name, recruiter_id) that change during the process; use foreign keys to slowly-changing dimension tables instead, and decide which version of that dimension you want (at posting, at hire, or all versions via SCD Type 2).
- **Late-arriving facts:** If job_filled_date arrives weeks after job_closed_date, use a merge/upsert pattern (dbt's `on_schema_change: fail`) and add a dbt_updated_at timestamp to track freshness.
- **Grain clarity:** Be explicit in naming and documentation—is this one row per job_id, or per job_id + candidate combination? Mis-specified grain causes joins to explode row counts silently.
- **Connects to:** Periodic snapshots (for "inventory at end of month"), transaction fact tables (granular events), and SCD Type 2 (when you need historical snapshots of slowly-changing dimensions like salary bands or role titles).
- **Revisit:** How to handle restarted or cancelled milestones (e.g., job_reopened_date); whether to track milestone *sequence* violations (filled before closed); and when to archive closed snapshots to a separate table for performance.
