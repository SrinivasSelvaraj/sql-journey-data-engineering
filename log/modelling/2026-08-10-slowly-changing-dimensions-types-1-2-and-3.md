---
date: 2026-08-10
phase: modelling
topic: Slowly changing dimensions types 1, 2 and 3
---

# Slowly changing dimensions types 1, 2 and 3

*Data modelling and warehousing*

## Concept

Slowly changing dimensions (SCDs) solve a critical problem: how to track changes in dimensional data over time while maintaining query clarity. When a job title changes, a salary gets updated, or a remote policy shifts, you must decide whether to overwrite history, preserve it, or do both. Without this design choice, your fact table either loses context (was that salary current then?) or becomes ambiguous (which job_title applies to which query date?).

SCDs matter most when business users ask time-sensitive questions: "What was the salary range when this person applied?" or "Show me remote jobs as of Q3." If you don't define your approach upfront, queries break into competing interpretations, and you'll rebuild your dimension tables mid-project.

The three types form a spectrum: Type 1 is simplest (overwrite), Type 2 is most common (full history via surrogate keys and validity dates), and Type 3 is rare (keep current + previous value). Choose based on query patterns and storage constraints, not hope.

## Practice

**Problem:** The `job_postings_fact` table references a job dimension, but job titles and remote eligibility change. When a job posting was filled, was that role remote? Did the title match the applicant's search? Historical analysis breaks without clarity.

**Solution:** Implement SCD Type 2 on a `jobs_dim` table:

```sql
-- Type 2: Track full history with surrogate key and validity dates
CREATE TABLE jobs_dim (
    job_dim_id INT PRIMARY KEY,  -- surrogate key
    job_id INT,                   -- natural key (business identifier)
    job_title_short VARCHAR(100),
    salary_year_avg DECIMAL(10,2),
    job_work_from_home BOOLEAN,
    job_location VARCHAR(100),
    is_current BOOLEAN,           -- flag for active record
    effective_date DATE,          -- when this version started
    end_date DATE,                -- when it became stale (NULL if current)
    dw_insert_ts TIMESTAMP        -- lineage
);

-- Fact table now points to the surrogate key
CREATE TABLE job_postings_fact (
    posting_id INT,
    job_dim_id INT,  -- FK to jobs_dim (not job_id)
    job_posted_date DATE,
    salary_year_avg DECIMAL(10,2),
    FOREIGN KEY (job_dim_id) REFERENCES jobs_dim(job_dim_id)
);

-- Query: "What was the remote policy when this job was posted?"
SELECT f.posting_id, d.job_work_from_home, d.effective_date
FROM job_postings_fact f
JOIN jobs_dim d ON f.job_dim_id = d.job_dim_id
WHERE f.job_posted_date BETWEEN d.effective_date AND COALESCE(d.end_date, CURRENT_DATE);
```

## Notes

- **Type 1 trap:** Overwriting old values seems efficient but destroys historical context. Use only for correcting errors, never for legitimate business changes.
- **Surrogate keys are essential:** Never join fact tables directly to natural keys when using SCD Type 2; the same job_id will have multiple rows. Always use the `job_dim_id` surrogate key.
- **Type 2 storage cost:** Each change spawns a new row. High-churn dimensions (stock prices, sensor readings) may need Type 3 (hybrid) or bucketing strategies instead.
- **Validity dates over flags:** `effective_date` and `end_date` are more robust than `is_current` flags when handling late-arriving facts or auditing edge cases.
- **Bridges to:** Conformed dimensions (sharing one clean jobs_dim across multiple fact tables), temporal databases (SQL standard for period-for-system-time), and audit tables (SCD logging for compliance).
