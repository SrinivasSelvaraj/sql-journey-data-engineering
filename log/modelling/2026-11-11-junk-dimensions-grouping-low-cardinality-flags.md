---
date: 2026-11-11
phase: modelling
topic: Junk dimensions: grouping low-cardinality flags
---

# Junk dimensions: grouping low-cardinality flags

*Data modelling and warehousing*

## Concept

A junk dimension groups low-cardinality flags and attributes (typically Boolean or small domains) into a single denormalized dimension table. Instead of creating separate dimension tables for each Boolean column—which wastes joins and storage—you combine them into one compact dimension keyed by a surrogate ID.

This matters because fact tables often accumulate many Boolean or small-domain columns over time: `is_active`, `is_remote`, `is_flagged_for_review`, `is_high_priority`. Without a junk dimension, your fact table becomes wide and cluttered, queries become harder to read, and analysts can't easily discover what flags exist. With it, you create a single reference point that documents the business logic and makes the fact table lean.

Without junk dimensions, low-cardinality flags either bloat the fact table directly (poor query readability and slow filtering) or spawn dozens of tiny, unmaintainable dimension tables (joining nightmare). Either way, downstream users won't know what combinations of flags are valid, and you'll field questions about what `job_work_from_home = true AND job_requires_travel = true` means.

## Practice

**Problem:** Your `job_postings_fact` table has four Boolean columns (`job_work_from_home`, `job_requires_travel`, `job_requires_clearance`, `job_is_contract`) plus a small domain column (`job_employment_type` with 5 values). The fact table is cluttered, and you want analysts to self-serve without guessing what combinations are valid.

**Solution:** Create a junk dimension and refactor.

```sql
-- Create junk dimension: job_terms_dim
CREATE TABLE job_terms_dim AS
SELECT
  ROW_NUMBER() OVER (ORDER BY work_from_home, requires_travel, requires_clearance, is_contract, employment_type) 
    AS job_terms_key,
  work_from_home,
  requires_travel,
  requires_clearance,
  is_contract,
  employment_type
FROM (
  SELECT DISTINCT
    job_work_from_home AS work_from_home,
    job_requires_travel AS requires_travel,
    job_requires_clearance AS requires_clearance,
    job_is_contract AS is_contract,
    job_employment_type AS employment_type
  FROM job_postings_fact
);

-- Refactored fact table
CREATE TABLE job_postings_fact_v2 AS
SELECT
  job_id,
  job_title_key,
  salary_year_avg,
  job_terms_key,  -- foreign key to junk dimension
  job_posted_date,
  location_key
FROM job_postings_fact
JOIN job_terms_dim jt
  ON job_postings_fact.job_work_from_home = jt.work_from_home
  AND job_postings_fact.job_requires_travel = jt.requires_travel
  AND job_postings_fact.job_requires_clearance = jt.requires_clearance
  AND job_postings_fact.job_is_contract = jt.is_contract
  AND job_postings_fact.job_employment_type = jt.employment_type;

-- Analyst query now reads clearly
SELECT
  jp.job_id,
  jp.job_title_short,
  jp.salary_year_avg,
  jt.work_from_home,
  jt.employment_type
FROM job_postings_fact_v2 jp
JOIN job_terms_dim jt ON jp.job_terms_key = jt.job_terms_key
WHERE jt.work_from_home = true AND jt.employment_type = 'Full-time';
```

## Notes

- **Cardinality threshold:** Junk dimensions work best when the product of distinct values is under 10K rows. Above that, you risk bloating the dimension and losing the benefit; consider splitting.
- **Surrogate keys:** Always use a surrogate key (like `job_terms_key`) in the junk dimension, not a natural key. This insulates your fact table from dimension changes and keeps joins fast.
- **Don't force it:** Not every flag needs a junk dimension. If you have one or two Boolean columns that change independently and have high business meaning, keep them in the fact table or link them to separate dimensions.
- **Adjacent concepts:** Relates closely to snowflaking, role-playing dimensions, and conformed dimensions in a bus matrix. Junk dimensions are the opposite of normalization—a pragmatic denormalization for readability.
- **Maintenance:** Document valid combinations in a data dictionary or add a `is_valid` flag to the junk dimension so analysts know which fact records are impossible states.
