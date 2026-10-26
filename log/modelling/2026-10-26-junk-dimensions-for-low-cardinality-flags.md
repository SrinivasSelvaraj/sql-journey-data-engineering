---
date: 2026-10-26
phase: modelling
topic: Junk dimensions for low-cardinality flags
---

# Junk dimensions for low-cardinality flags

*Data modelling and warehousing*

## Concept

A junk dimension is a single dimension table that consolidates low-cardinality flags and indicators—typically Boolean or small-domain columns—that would otherwise clutter your fact table or create wasteful one-column dimension tables. Instead of storing `job_work_from_home`, `job_is_urgent`, and `job_is_internal` as separate columns in `job_postings_fact`, you create a compact dimension with all combinations and join via a surrogate key.

This matters because Boolean columns are often added ad hoc as business needs evolve. Without a junk dimension, your fact table becomes wider and harder to interpret; with it, you have a single reference point for what each flag combination means. It also compresses storage: a single `junk_dim_id` integer uses less space than three separate Boolean columns, and queries self-document better when they reference a dimension name rather than scattered flags.

Without a junk dimension strategy, you end up with fact tables that have 10+ scattered Boolean/small-domain columns, making queries ambiguous ("does `is_remote` mean the job *can be* remote or *must be* remote?") and forcing analysts to ask you for clarification. A junk dimension centralizes definition and makes the warehouse self-service.

## Practice

**Problem:** Your `job_postings_fact` table has grown to include `job_work_from_home`, `job_is_urgent`, and `job_is_contract`. Analysts constantly confuse whether these are filtering criteria or job attributes, and the fact table is becoming difficult to navigate.

```sql
-- Create the junk dimension
CREATE TABLE junk_dim_job_flags (
  junk_dim_id INT PRIMARY KEY,
  work_from_home BOOLEAN,
  is_urgent BOOLEAN,
  is_contract BOOLEAN,
  flag_description VARCHAR(255)
);

INSERT INTO junk_dim_job_flags VALUES
  (1, FALSE, FALSE, FALSE, 'Office-based, standard priority, permanent role'),
  (2, TRUE, FALSE, FALSE, 'Remote-eligible, standard priority, permanent role'),
  (3, FALSE, TRUE, FALSE, 'Office-based, urgent hire, permanent role'),
  (4, TRUE, TRUE, TRUE, 'Remote-eligible, urgent hire, contract role');
  -- ... and so on for all 2^3 = 8 combinations

-- Refactor fact table
ALTER TABLE job_postings_fact 
  DROP COLUMN job_work_from_home,
  DROP COLUMN job_is_urgent,
  DROP COLUMN job_is_contract,
  ADD COLUMN junk_dim_id INT REFERENCES junk_dim_job_flags;

-- Query becomes clear
SELECT jp.job_id, jp.job_title_short, jp.salary_year_avg, jd.flag_description
FROM job_postings_fact jp
JOIN junk_dim_job_flags jd ON jp.junk_dim_id = jd.junk_dim_id
WHERE jd.work_from_home = TRUE AND jd.is_urgent = TRUE;
```

## Notes

- **Don't over-apply:** Only use junk dimensions for true low-cardinality flags (Boolean, small enums). If a column has 100+ distinct values, it deserves its own dimension.
- **Pre-compute the matrix:** Generate all possible flag combinations upfront, even unused ones. This prevents gaps when new combinations appear and keeps the dimension static.
- **Add a description field:** Always include a human-readable summary in the junk dimension so analysts understand *why* each combination exists and what it means operationally.
- **Version it carefully:** If you add a new flag later, create `junk_dim_job_flags_v2` rather than mutating the original, to avoid breaking historical queries and audit trails.
- **Related to:** conformed dimensions, slowly changing dimensions (SCD Type 1), and normalization trade-offs—junk dimensions are an intentional denormalization for clarity and query performance.
