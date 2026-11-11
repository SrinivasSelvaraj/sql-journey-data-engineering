---
date: 2026-11-11
phase: modelling
topic: Slowly changing dimensions: type 0, 1, 2 and hybrid
---

# Slowly changing dimensions: type 0, 1, 2 and hybrid

*Data modelling and warehousing*

## Concept

Slowly changing dimensions (SCDs) handle how to store historical changes in dimension tables—things like employee titles, product categories, or job descriptions that evolve over time but aren't transaction data. Without an SCD strategy, you either lose history (overwrite old values), bloat your fact table with redundant columns, or create a mess of flags that no one understands six months later.

The three main types solve different problems: **Type 0** never changes (immutable); **Type 1** overwrites (only current state); **Type 2** maintains full history with validity dates (rows for each version); **Type 3** keeps current plus one prior version (limited history). Choose based on audit requirements and query patterns. A hybrid approach—e.g., Type 1 for low-value changes + Type 2 for critical ones—is common in production warehouses.

Without this design, you'll either rewrite fact tables to "fix" historical context (losing auditability), create convoluted logic in BI tools to guess which dimension version applies to which fact, or end up with analysts querying the wrong snapshot and getting contradictory answers to the same business question.

## Practice

**Problem:** Job titles in your job_postings_fact change over time as companies relabel roles (e.g., "Software Engineer" → "Software Engineer II" → "Senior Software Engineer"). You need to track when each title was active and ensure historical queries show the title that was posted, not today's current title.

```sql
-- Type 2 SCD: job_titles_dim with full history
CREATE TABLE job_titles_dim (
    job_title_key SERIAL PRIMARY KEY,
    job_title_short VARCHAR(100),
    job_title_full VARCHAR(255),
    dw_start_date DATE,
    dw_end_date DATE,
    is_current BOOLEAN
);

-- Initial load
INSERT INTO job_titles_dim VALUES
    (1, 'SWE', 'Software Engineer', '2023-01-01', '2024-12-31', FALSE),
    (2, 'SWE', 'Software Engineer II', '2025-01-01', '9999-12-31', TRUE);

-- Fact table references the dimension key
CREATE TABLE job_postings_fact (
    job_id INT,
    job_title_key INT REFERENCES job_titles_dim(job_title_key),
    salary_year_avg NUMERIC,
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    job_location VARCHAR(100)
);

-- Query: what title was active when this job was posted?
SELECT f.job_id, d.job_title_full, f.salary_year_avg
FROM job_postings_fact f
JOIN job_titles_dim d ON f.job_title_key = d.job_title_key
WHERE f.job_posted_date BETWEEN d.dw_start_date AND d.dw_end_date;
```

## Notes

- **Type 1 vs. Type 2 trade-off:** Type 1 (overwrite) saves storage and simplifies queries but erases audit trail; Type 2 preserves history but doubles row counts and requires date-range logic in every join.
- **The `is_current` flag** is a shortcut for "give me today's version," but it's redundant if you use `dw_end_date = '9999-12-31'`; choose one convention and document it.
- **Hybrid in practice:** Use Type 1 for cosmetic changes (typos, formatting), Type 2 for business-critical attributes (compensation bands, job categories, compliance-tracked fields).
- **Bridges to:** conformed dimensions (ensuring the same dimension is reused across multiple facts), slowly growing fact tables (when facts themselves change), and temporal queries (ASOF joins, AS OF syntax in some warehouses).
- **Common mistake:** Applying SCD logic to fact tables instead of dimensions—facts should be immutable; if you're changing a fact, you have a data quality problem upstream.
