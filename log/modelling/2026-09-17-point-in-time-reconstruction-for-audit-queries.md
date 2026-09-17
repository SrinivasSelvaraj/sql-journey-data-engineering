---
date: 2026-09-17
phase: modelling
topic: Point-in-time reconstruction for audit queries
---

# Point-in-time reconstruction for audit queries

*Data modelling and warehousing*

## Concept

Point-in-time reconstruction lets you query historical data *as it existed on a specific date*, not just see the current state. Without it, you lose the ability to audit what changed, when it changed, and why. A job posting might have had salary $80k in January and $95k by March—if you only store the current value, you can't answer "what was the salary range we advertised on Feb 15?"

This matters most for compliance, root-cause analysis, and understanding user behavior across time. Financial audits, GDPR requests, and fraud investigation all depend on it. Without versioning logic, you either overwrite history or bloat your tables with duplicate snapshots.

The schema pattern uses either *slowly changing dimensions* (SCD Type 2) with effective/expiration dates, or an immutable event log with timestamps. The choice depends on query patterns: use SCD Type 2 when you need to join historical facts to a slowly changing reference, and use event logs when you need fine-grained audit trails.

## Practice

**Problem:** A recruiter wants to know: "Which jobs were advertised as remote on 2024-06-01, and what salary did we show for each?"—but job postings get edited constantly (location changes, salary adjusts). Your current schema has no history.

```sql
-- Schema addition: add effective date tracking
CREATE TABLE job_postings_fact (
    job_id INT,
    job_title_short VARCHAR,
    salary_year_avg DECIMAL,
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    job_location VARCHAR,
    effective_date DATE,       -- When this row became valid
    expiration_date DATE,      -- When it was replaced (NULL = current)
    is_current BOOLEAN         -- Flag for fast filtering
);

-- Query: state of all remote jobs on 2024-06-01
SELECT job_id, job_title_short, salary_year_avg, job_location
FROM job_postings_fact
WHERE effective_date <= '2024-06-01'
  AND (expiration_date > '2024-06-01' OR expiration_date IS NULL)
  AND job_work_from_home = TRUE;
```

## Notes

- **SCD Type 1 (overwrite) is not audit-safe**—it destroys history. Use it only for corrections or data quality fixes, never for domain changes.
- **Grain matters**: decide whether a row represents a job posting *version* (one row per change) or a *daily snapshot* (one row per job per day). Snapshots cost more storage but simplify joins; versions are cheaper but need careful aggregation.
- **NULL handling**: use `expiration_date IS NULL` (not `= '9999-12-31'`) to flag current records—it's clearer and avoids year-9999 edge cases in reporting.
- **Adjacent topics**: connects directly to *fact table grain*, *slowly changing dimensions*, and *temporal joins*. Also intersects with *data lineage* (tracking where values came from) and *idempotent transformations* (ensuring re-runs don't create duplicates).
- **Common mistake**: adding effective dates retroactively to existing tables. Plan the versioning strategy before loading; retrofitting is painful and error-prone.
