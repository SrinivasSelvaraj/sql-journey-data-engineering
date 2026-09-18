---
date: 2026-09-18
phase: modelling
topic: Atomic transaction markers for consistency
---

# Atomic transaction markers for consistency

*Data modelling and warehousing*

## Concept

Atomic transaction markers are metadata fields that ensure a fact table row represents a complete, consistent snapshot of reality at a point in time. The most common marker is a `dbt_loaded_at` or `loaded_at` timestamp that records when a row entered the warehouse—not when the source event occurred. This separates source-time semantics from pipeline-time semantics, preventing confusion when late-arriving or corrected data arrives.

Without atomic markers, a querier cannot distinguish between "this job posting was live on 2024-01-15" and "we learned about this job posting on 2024-01-15." When a record is updated (salary corrected, location changed, or a duplicate removed), you lose visibility into whether a query result is stale or current. This matters most in compliance-heavy domains and when your fact table is the source of truth for reporting.

Markers also enable idempotent loads: if a pipeline reruns, you can safely upsert rows where the marker and key already exist, rather than duplicating data or breaking downstream queries mid-day.

## Practice

**Problem:** The `job_postings_fact` table is queried to report "active listings by location on each day." Yesterday's report showed 412 postings in Austin; today it shows 389. You don't know if 23 listings expired, if they were deleted from the source, or if a data quality fix removed duplicates.

**Solution:** Add an atomic marker and soft-delete flag:

```sql
CREATE TABLE job_postings_fact (
  job_id INT,
  job_title_short VARCHAR,
  salary_year_avg DECIMAL,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR,
  dbt_loaded_at TIMESTAMP,      -- when row entered warehouse
  is_deleted BOOLEAN DEFAULT FALSE,
  PRIMARY KEY (job_id, dbt_loaded_at)
);

-- Query: active listings in Austin as of 2024-01-15
SELECT COUNT(*)
FROM job_postings_fact
WHERE job_location = 'Austin'
  AND job_posted_date <= '2024-01-15'
  AND is_deleted = FALSE
  AND dbt_loaded_at = (SELECT MAX(dbt_loaded_at) FROM job_postings_fact WHERE dbt_loaded_at <= '2024-01-15 23:59:59');
```

## Notes

- **Loaded-at ≠ Posted-at:** Confusing pipeline timestamp with source timestamp is the most common mistake. Always clarify in the column docstring which one a timestamp represents.
- **Soft deletes over hard deletes:** Never remove rows; mark them deleted and keep history. Downstream dashboards and audits depend on immutability.
- **Idempotency pattern:** Use `MERGE` or `INSERT … ON CONFLICT` keyed on `(natural_key, dbt_loaded_at)` to make reruns safe and reproducible.
- **Connects to:** Slowly Changing Dimensions (SCD Type 2), data lineage, audit tables, and dbt `updated_at` macros for incremental models.
- **Revisit:** How to handle same-day corrections (do you overwrite or version?) and how to design fact tables that support both point-in-time and change-tracking queries.
