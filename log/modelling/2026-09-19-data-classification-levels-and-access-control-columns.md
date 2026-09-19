---
date: 2026-09-19
phase: modelling
topic: Data classification levels and access control columns
---

# Data classification levels and access control columns

*Data modelling and warehousing*

## Concept

Data classification assigns sensitivity levels (public, internal, confidential, restricted) to columns, enabling self-service analytics without exposing sensitive information or creating compliance violations. Without explicit classification, teams either over-restrict access (blocking legitimate analysis) or under-restrict it (leaking PII or financial data). In a data warehouse, classification drives column-level access control: who can query salary ranges, which roles see candidate names, whether geographic data is aggregated or precise.

Classification becomes critical when scaling beyond a single analyst. A junior data scientist shouldn't query individual salaries by location (privacy risk), but aggregated salary trends by region are safe. A recruiter needs exact job locations; finance needs salary bands. Without schema-level documentation of these boundaries, you become a bottleneck answering "can I see this column?"—and inconsistent decisions erode trust.

Implement classification at design time by adding metadata columns or documentation that travels with your schema. Tools like Apache Atlas, dbt metadata, or warehouse native policies (Snowflake tags, Redshift column-level security) codify rules so access happens automatically rather than through manual review.

## Practice

**Problem:** Your `job_postings_fact` table includes `salary_year_avg`, which finance needs to see but should be hidden from external partners. You also want recruiters to access individual job locations but anonymize salary data for trend reporting. How do you structure this?

```sql
-- Add classification metadata to your schema
CREATE TABLE job_postings_fact (
    job_id INT,
    job_title_short VARCHAR(100),
    salary_year_avg INT COMMENT 'CLASSIFICATION: CONFIDENTIAL | Finance, Data Science only',
    job_work_from_home BOOLEAN COMMENT 'CLASSIFICATION: PUBLIC',
    job_posted_date DATE COMMENT 'CLASSIFICATION: INTERNAL',
    job_location VARCHAR(100) COMMENT 'CLASSIFICATION: INTERNAL | Precise location; aggregate for external reports'
);

-- Create a public view for external partners (no salary data)
CREATE VIEW job_postings_public AS
SELECT 
    job_id,
    job_title_short,
    job_work_from_home,
    job_posted_date,
    CONCAT(SPLIT_PART(job_location, ',', 2), ', US') AS job_region  -- Anonymize to state level
FROM job_postings_fact;

-- Create an internal view for recruiter use (precise locations, no salary)
CREATE VIEW job_postings_internal_recruiting AS
SELECT 
    job_id,
    job_title_short,
    job_work_from_home,
    job_posted_date,
    job_location
FROM job_postings_fact;

-- Finance and data science access the base table with salary
```

## Notes

- **Classification without enforcement = documentation theater.** Add COMMENT metadata, then enforce it via role-based access control in your warehouse (Snowflake dynamic masking, Redshift RLS, BigQuery IAM) or lose trust immediately.
- **Salary data is almost always confidential.** Location, job title, and dates are usually safe to share widely unless combined with salary (creates a PII+financial hybrid). Default to restrictive; expand access explicitly.
- **Aggregation ≠ anonymization.** Salary averages by location + job title can still re-identify individuals in small teams. Document minimum group sizes or apply differential privacy if needed.
- **Classification connects to metadata governance.** Link it to your data dictionary, lineage tracking, and retention policies so teams understand the *why* behind access rules, not just the rules themselves.
- **Revisit quarterly:** as new use cases emerge (hiring forecasts, equity analysis), classification may tighten or loosen. Document changes in your dbt yml or Atlas to avoid surprise access denials.
