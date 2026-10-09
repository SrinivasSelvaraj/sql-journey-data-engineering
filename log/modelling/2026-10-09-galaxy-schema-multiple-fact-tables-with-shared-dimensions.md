---
date: 2026-10-09
phase: modelling
topic: Galaxy schema: multiple fact tables with shared dimensions
---

# Galaxy schema: multiple fact tables with shared dimensions

*Data modelling and warehousing*

## Concept

A galaxy schema (also called a fact constellation) extends the star schema by allowing multiple fact tables to share the same dimension tables. Instead of one central fact table, you have several related fact tables—each representing a different business process—all connecting to common, reusable dimensions. This matters because real organizations don't fit neatly into one fact table: you might track job postings, applications, hires, and departures as separate facts, but they all describe the same job, location, and company.

Without a galaxy schema, you either duplicate dimensions across schemas (creating maintenance nightmares and inconsistent definitions) or force unrelated processes into a single fact table (creating sparse, slow, hard-to-query tables). A galaxy schema keeps dimension definitions single-sourced while letting your analytics team query multiple business processes independently—without asking you what "job_location" actually means across different analyses.

The key insight: dimensions are contracts. Once you define `dim_location`, every fact table that references it uses *that same definition*. This eliminates "does this include remote or not?" arguments and makes lineage traceable.

## Practice

**Problem:** You have job_postings_fact, but the business also needs to track job applications separately. An application references a job posting, but also has its own attributes (application status, candidate experience level, interview_date). You need both fact tables to query together without duplicating location or job metadata.

```sql
-- Dimension tables (shared by multiple fact tables)
CREATE TABLE dim_job (
    job_id INT PRIMARY KEY,
    job_title_short VARCHAR(50),
    job_category VARCHAR(100),
    created_date DATE
);

CREATE TABLE dim_location (
    location_id INT PRIMARY KEY,
    location_name VARCHAR(100),
    country VARCHAR(50),
    is_remote BOOLEAN
);

-- Fact table 1: job postings
CREATE TABLE fact_job_postings (
    posting_id INT PRIMARY KEY,
    job_id INT REFERENCES dim_job(job_id),
    location_id INT REFERENCES dim_location(location_id),
    salary_year_avg DECIMAL(10,2),
    job_posted_date DATE
);

-- Fact table 2: job applications (different grain, same dimensions)
CREATE TABLE fact_job_applications (
    application_id INT PRIMARY KEY,
    job_id INT REFERENCES dim_job(job_id),
    location_id INT REFERENCES dim_location(location_id),
    application_date DATE,
    application_status VARCHAR(50),
    candidate_experience_years INT
);

-- Query across both facts without ambiguity
SELECT
    dj.job_title_short,
    dl.location_name,
    COUNT(DISTINCT fjp.posting_id) AS num_postings,
    COUNT(DISTINCT fja.application_id) AS num_applications
FROM dim_job dj
LEFT JOIN dim_location dl ON 1=1  -- cartesian if needed, or filter
LEFT JOIN fact_job_postings fjp ON dj.job_id = fjp.job_id
LEFT JOIN fact_job_applications fja ON dj.job_id = fja.job_id
GROUP BY dj.job_title_short, dl.location_name;
```

## Notes

- **Dimension reuse is the win.** If you find yourself recreating the same location or job attributes in multiple fact tables, you've broken the contract—extract it into a shared dimension immediately.
- **Foreign keys anchor quality.** Enforce referential integrity on dimension keys; a fact row pointing to a non-existent dimension ID is a silent bug.
- **Grain clarity prevents joins gone wrong.** Each fact table has its own grain (one row per posting vs. one row per application). Document this or your teammates will inner-join them incorrectly.
- **Conformed dimensions connect to Data Vault and dimensional modeling.** A galaxy schema is the practical form of conformed dimensions; it bridges dimensional modeling and more flexible schemas like Data Vault hubs/links.
- **Revisit when: business processes diverge.** If two fact tables share only 30% of dimensions, consider splitting them or introducing a bridge table instead of forcing a join.
