---
date: 2026-09-16
phase: modelling
topic: Degenerate dimensions and factless fact tables
---

# Degenerate dimensions and factless fact tables

*Data modelling and warehousing*

## Concept

A **degenerate dimension** is a dimension attribute that lives in a fact table instead of in a separate dimension table. It's a column like `job_title_short` or `job_posted_date` that describes the transaction but has no meaningful hierarchy, lookup table, or need for slow-changing dimension logic. Use degenerate dimensions when the attribute is either too low-cardinality to justify a dimension table, changes too frequently to track separately, or is already a natural key of the fact itself (like an order number or job posting ID).

A **factless fact table** records events or relationships with no numeric measures—only dimensions and keys. Common examples: attendance records (who was present when), equipment maintenance logs (what broke and when it was serviced), or student course enrollments (which student took which course in which term). Without factless fact tables, teams force artificial measures into schemas (count = 1, duration = NULL) and lose the ability to ask "what happened?" independently of "how much."

Both patterns prevent schema fragmentation and premature normalization. When you skip them, you either duplicate dimension logic across queries or build fact tables that lie about what they actually measure.

## Practice

**Problem:** The schema above mixes dimensions and facts poorly. `job_title_short` and `job_location` belong in a dimension table so analysts can filter and group without ambiguity. Also, you want to track *job postings that received no applications*—a factless fact table scenario.

**Solution:**

```sql
-- Degenerate dimension: keep transaction-level, non-lookup attributes in fact
CREATE TABLE job_postings_fact (
    job_posting_id INT PRIMARY KEY,
    job_id INT NOT NULL,
    job_posted_date DATE NOT NULL,
    salary_year_avg DECIMAL(10, 2),
    job_work_from_home BOOLEAN,
    FOREIGN KEY (job_id) REFERENCES job_dim(job_id)
);

-- Separate dimension table for lookups and analytics
CREATE TABLE job_dim (
    job_id INT PRIMARY KEY,
    job_title_short VARCHAR(100),
    job_location VARCHAR(100),
    job_category VARCHAR(50),
    dw_insert_date DATE
);

-- Factless fact table: enrollment without measures
CREATE TABLE job_application_event (
    job_posting_id INT NOT NULL,
    candidate_id INT NOT NULL,
    application_date DATE NOT NULL,
    PRIMARY KEY (job_posting_id, candidate_id, application_date),
    FOREIGN KEY (job_posting_id) REFERENCES job_postings_fact(job_posting_id),
    FOREIGN KEY (candidate_id) REFERENCES candidate_dim(candidate_id)
);

-- Now you can find zero-application postings
SELECT jp.job_posting_id, jd.job_title_short, jp.salary_year_avg
FROM job_postings_fact jp
JOIN job_dim jd ON jp.job_id = jd.job_id
LEFT JOIN job_application_event jae ON jp.job_posting_id = jae.job_posting_id
WHERE jae.job_posting_id IS NULL;
```

## Notes

- **Degenerate dimensions create schema clarity:** analysts don't ask "why is `job_title` here?" because it's obviously a transaction detail, not a lookup. Keep only immutable or transaction-bound attributes in the fact table.
- **Factless fact tables are invisible to beginners:** the temptation is always to add a `COUNT(*) = 1` measure. Resist. If there's no numeric outcome, you don't need a measure—you need a junction table with timestamps.
- **Slow-changing dimensions don't belong degenerate:** if `job_title` changes meaning over time, move it to `job_dim` with SCD Type 2 (effective dates). Degenerate attributes must be static within a transaction.
- **Connects to:** conformed dimensions (shared job_dim across schemas), fact table granularity (one row per job posting, not per application), and slowly changing dimensions (SCD patterns for dimension attributes).
- **Revisit:** how to handle many-to-many relationships (candidate ↔ job via factless table) and when a factless table signals you should have measured something differently upstream.
