---
date: 2026-09-17
phase: modelling
topic: Is_current flag and validity date ranges
---

# Is_current flag and validity date ranges

*Data modelling and warehousing*

## Concept

An `is_current` flag is a boolean column that marks whether a record represents the present state of an entity, while validity date ranges (`valid_from` and `valid_to` timestamps) define the temporal window when a record is factually accurate. Together, they solve the **slowly changing dimension (SCD) problem**—how to track when attributes change without overwriting history.

Without these markers, you cannot distinguish whether a row is outdated, active, or pending. A user asking "what was the salary range for this job when it was posted?" has no way to know which salary row to trust. Similarly, downstream consumers building reports won't know if they're analyzing current state or stale data, leading to incorrect metrics and decisions made without context.

In practice: use `is_current = TRUE` only for the active version of a record, and populate `valid_from` / `valid_to` on every version so any query can filter to a specific point in time (`WHERE valid_from <= '2024-01-15' AND valid_to > '2024-01-15'`). This enables reproducible historical analysis and protects against accidental use of superseded data.

## Practice

**Problem:** The `job_postings_fact` table is missing temporal logic. A job's salary was posted at $80k in January, but the company updated it to $95k in March. Analysts running reports in April cannot tell which salary to use, and there's no audit trail. How do you restructure this to support "show me what we knew on 2024-02-01"?

```sql
-- Redesigned table with SCD Type 2 logic
CREATE TABLE job_postings_fact (
  job_posting_id INT,
  job_id INT,
  job_title_short VARCHAR(100),
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(100),
  valid_from TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  valid_to TIMESTAMP DEFAULT '9999-12-31 23:59:59',
  is_current BOOLEAN DEFAULT TRUE,
  dbt_scd_id VARCHAR(32) -- unique key per version
);

-- When salary updates, expire old row and add new one
UPDATE job_postings_fact 
SET is_current = FALSE, valid_to = CURRENT_TIMESTAMP 
WHERE job_id = 12345 AND is_current = TRUE;

INSERT INTO job_postings_fact 
VALUES (NULL, 12345, 'Data Engineer', 95000, TRUE, '2024-01-15', 'NYC', 
        CURRENT_TIMESTAMP, '9999-12-31 23:59:59', TRUE, MD5('12345||v2'));

-- Query salary as of Feb 1, 2024
SELECT salary_year_avg 
FROM job_postings_fact 
WHERE job_id = 12345 
  AND valid_from <= '2024-02-01' 
  AND valid_to > '2024-02-01';
```

## Notes

- **Don't set `valid_to` to NULL for current records**—use a far-future sentinel date like `'9999-12-31'` so range queries work consistently without NULL-handling logic.
- **Denormalize `is_current` even though it's derivable**—`WHERE is_current = TRUE` is faster and clearer for analysts than `WHERE valid_to = (SELECT MAX(valid_to))`.
- **SCD Type 2 (versioning) vs. Type 1 (overwrite)**—Type 2 is standard in warehouses; Type 1 loses history and only works if you never need to audit changes.
- **Connect this to grain and keys**—your fact table's grain (one row per job posting per version) determines whether you need a surrogate `dbt_scd_id` or can rely on `(job_id, valid_from)`.
- **Test edge cases**: what happens at `valid_from = valid_to`? Handle overlapping periods in ETL or they'll cause duplicate-row bugs in joins.
