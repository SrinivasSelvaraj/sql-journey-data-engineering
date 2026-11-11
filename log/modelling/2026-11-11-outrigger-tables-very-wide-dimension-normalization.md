---
date: 2026-11-11
phase: modelling
topic: Outrigger tables: very wide dimension normalization
---

# Outrigger tables: very wide dimension normalization

*Data modelling and warehousing*

## Concept

An outrigger table is a normalized dimension attached to another dimension rather than directly to a fact table. It solves the "very wide dimension" problem: when a dimension has so many attributes that it becomes unwieldy, or when some attributes are shared by only a subset of dimension members, you split it into a main dimension and one or more outrigger dimensions linked by a foreign key.

Without outriggers, you end up with sparse columns (mostly NULLs), slow dimension updates (changing one attribute requires reloading thousands of rows), or dimension tables so wide they're difficult to maintain and query. For example, a job posting dimension with 50+ attributes about hiring practices, benefits, company culture, visa sponsorship policies, and growth opportunities creates both storage waste and cognitive overhead for analysts.

Outriggers are particularly valuable in slowly changing dimensions (SCD Type 2) where you want to track history on some attributes but not others. They also improve query performance by reducing the number of columns a query must scan and allowing the dimension to fit in memory more efficiently.

## Practice

**Problem:** Your `job_postings_fact` table is becoming unwieldy because job postings have 15+ boolean and text attributes about benefits (remote_eligible, visa_sponsorship, sign_on_bonus, relocation_assistance, equity_offered, etc.). Every query that filters on visa sponsorship must scan through columns irrelevant to most analyses. New benefit types appear monthly, requiring constant schema changes.

**Solution:** Create a `job_benefits_outrigger` dimension and link it via the main job dimension:

```sql
-- Main dimension: core job attributes only
CREATE TABLE dim_job (
    job_key INT PRIMARY KEY,
    job_id VARCHAR(50) UNIQUE,
    job_title VARCHAR(255),
    job_category_key INT FOREIGN KEY REFERENCES dim_job_category,
    job_posted_date DATE,
    benefits_outrigger_key INT FOREIGN KEY REFERENCES dim_job_benefits
);

-- Outrigger dimension: all benefits as a shared entity
CREATE TABLE dim_job_benefits (
    benefits_outrigger_key INT PRIMARY KEY,
    remote_eligible BOOLEAN,
    visa_sponsorship BOOLEAN,
    sign_on_bonus BOOLEAN,
    relocation_assistance BOOLEAN,
    equity_offered BOOLEAN,
    parental_leave_weeks INT,
    401k_match_pct DECIMAL(5,2),
    dbt_load_ts TIMESTAMP
);

-- Fact table references main dimension only
CREATE TABLE job_postings_fact (
    job_posting_id INT PRIMARY KEY,
    job_key INT FOREIGN KEY REFERENCES dim_job,
    salary_year_avg DECIMAL(10,2),
    applications_received INT,
    posted_date DATE
);

-- Clean query: benefits are logically grouped, easy to add new ones
SELECT j.job_title, COUNT(*) as count
FROM job_postings_fact f
JOIN dim_job j ON f.job_key = j.job_key
JOIN dim_job_benefits b ON j.benefits_outrigger_key = b.benefits_outrigger_key
WHERE b.visa_sponsorship = TRUE
  AND b.remote_eligible = TRUE
GROUP BY j.job_title;
```

## Notes

- **Don't over-normalize:** Outriggers should represent coherent, reusable business concepts (e.g., benefits, geographic attributes, compliance flags). Random groupings of leftover columns create confusion.
- **Links to SCD strategies:** Outriggers are especially powerful with Type 2 SCDs—you can version the outrigger independently from the main dimension, capturing when benefits policies change without full dimension reloads.
- **Revisit cardinality:** If the outrigger has one-to-one cardinality with the main dimension (each job has unique benefits), you've just created extra joins for no benefit—fold it back into the main dimension.
- **Watch for sparse linkage:** If only 10% of dimensions use an outrigger, consider whether it belongs in a separate fact or attribute table instead; excessive NULLs in the foreign key suggest poor grain definition.
- **Related to conformed dimensions:** Outriggers work well when multiple fact tables need the same benefits logic; use conformed outriggers to ensure consistency across subject areas.
