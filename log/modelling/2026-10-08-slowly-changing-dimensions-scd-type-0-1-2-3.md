---
date: 2026-10-08
phase: modelling
topic: Slowly changing dimensions: SCD Type 0, 1, 2, 3
---

# Slowly changing dimensions: SCD Type 0, 1, 2, 3

*Data modelling and warehousing*

## Concept

Slowly changing dimensions (SCD) define how you handle attribute changes in dimension tables over time. When a dimension attribute changes—a job title gets renamed, an employee's department shifts, a product's category is reclassified—you must decide: overwrite the old value, keep history, or do something in between. Without an SCD strategy, you lose either historical accuracy (overwriting) or create query ambiguity (keeping conflicting versions without tracking when each was valid).

SCD matters because business questions depend on temporal clarity. "How many data engineers did we hire in 2022?" requires knowing job titles as they existed then, not today's renamed versions. The wrong SCD choice creates silent data quality issues: analysts query the fact table, join to dimensions, and get the current dimension values mixed with historical facts, producing unreliable aggregations and trend analysis.

## Practice

**Problem:** Job postings arrive with job titles that change over time (e.g., "Data Analyst" becomes "Analytics Engineer"). You need historical fact records to always show the job title *as it was posted*, not the current title. Simultaneously, you want to filter or group by current job titles in recent queries. Design a dimension table and fact table to support both.

```sql
-- SCD Type 2: Track history with effective/end dates
CREATE TABLE dim_job_title (
    job_title_key SERIAL PRIMARY KEY,
    job_id INT NOT NULL,
    job_title_short VARCHAR(100) NOT NULL,
    effective_date DATE NOT NULL,
    end_date DATE,
    is_current BOOLEAN DEFAULT TRUE
);

-- Fact table links to dimension key, not raw title
CREATE TABLE job_postings_fact (
    job_posting_id SERIAL PRIMARY KEY,
    job_id INT NOT NULL,
    job_title_key INT NOT NULL REFERENCES dim_job_title(job_title_key),
    salary_year_avg DECIMAL,
    job_work_from_home BOOLEAN,
    job_posted_date DATE NOT NULL,
    job_location VARCHAR(255)
);

-- When a job title changes, insert a new row in dim_job_title
INSERT INTO dim_job_title (job_id, job_title_short, effective_date, is_current)
VALUES (42, 'Analytics Engineer', '2024-01-15', TRUE);

UPDATE dim_job_title 
SET is_current = FALSE, end_date = '2024-01-14'
WHERE job_id = 42 AND job_title_short = 'Data Analyst';

-- Query: postings with the title *as it was posted*
SELECT f.job_posted_date, d.job_title_short, f.salary_year_avg
FROM job_postings_fact f
JOIN dim_job_title d ON f.job_title_key = d.job_title_key
WHERE f.job_posted_date BETWEEN '2023-01-01' AND '2024-01-31';
```

## Notes

- **SCD Type 0** (none): attribute never changes—use it for immutable identifiers. Type 1 (overwrite): simplest, loses history; okay for corrections only. Type 2 (add rows with dates): preserves full history, requires effective/end date columns and surrogate keys. Type 3 (add columns): tracks only current and previous; saves space but limited to one prior version.
- **Surrogate keys are essential with SCD Type 2**: the fact table must reference a dimension row *version*, not just the business key, or you'll join to the wrong (current) title when querying historical facts.
- **Avoid mixing fact dates with dimension dates**: job_posted_date lives in the fact table; effective_date belongs in the dimension. Joining on both prevents silent mismatches.
- **Slowly *changing***: the name means attributes change infrequently. If job titles flip daily, you have a data quality problem upstream, not an SCD problem.
- **Adjacent topics**: conformed dimensions (shared across fact tables), bridge tables (for many-to-many dimension attributes), and temporal modeling (CTEs with window functions for point-in-time analysis).
