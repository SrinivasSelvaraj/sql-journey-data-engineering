---
date: 2026-09-17
phase: modelling
topic: Kimball vs Inmon approaches and when each fits
---

# Kimball vs Inmon approaches and when each fits

*Data modelling and warehousing*

## Concept

The **Kimball approach** (dimensional modeling) organizes data into star schemas: a central fact table surrounded by dimension tables. Each fact records a business event (a job posting) with foreign keys pointing to slowly-changing dimensions (location, title, company). The **Inmon approach** (3NF) normalizes everything into highly structured, interdependent tables to minimize redundancy and enforce consistency at write time.

Kimball wins when analysts query first and schema changes are infrequent—denormalization trades storage for query speed and simplicity. Inmon wins when data integrity, compliance, or frequent schema updates matter more than query convenience. In practice, most modern teams use Kimball for the presentation layer (what analysts see) and Inmon principles for the operational layer (what systems write to).

Without clarity on your approach, you end up with a messy hybrid: queries require three joins just to get a job title, or your fact table has 200 columns nobody understands. Your users ask "what does job_title_short mean?" because the logic lives in undocumented ETL code, not in the schema itself.

## Practice

**Problem:** Your `job_postings_fact` table has salary, location, and work-from-home status all mixed in. A new analyst needs to answer: "What's the average salary for remote vs. on-site roles, broken down by location?" They don't know which columns are dimensions vs. metrics, and location is just text with no way to group by region.

**Kimball solution:**

```sql
-- Create dimension tables
CREATE TABLE dim_location (
    location_key INT PRIMARY KEY,
    location_name VARCHAR(255),
    city VARCHAR(100),
    country VARCHAR(100),
    region VARCHAR(100)
);

CREATE TABLE dim_job_type (
    job_type_key INT PRIMARY KEY,
    work_from_home BOOLEAN,
    type_name VARCHAR(50)
);

-- Denormalized fact table pointing to dimensions
CREATE TABLE job_postings_fact (
    job_id INT,
    location_key INT REFERENCES dim_location(location_key),
    job_type_key INT REFERENCES dim_job_type(job_type_key),
    salary_year_avg DECIMAL(10, 2),
    job_posted_date DATE,
    job_count INT DEFAULT 1  -- measure
);

-- Now the query is self-documenting
SELECT
    l.region,
    jt.type_name,
    AVG(f.salary_year_avg) AS avg_salary,
    COUNT(*) AS posting_count
FROM job_postings_fact f
JOIN dim_location l ON f.location_key = l.location_key
JOIN dim_job_type jt ON f.job_type_key = jt.job_type_key
GROUP BY l.region, jt.type_name
ORDER BY l.region, avg_salary DESC;
```

The schema now screams: "Salary is a metric, location and work-from-home are dimensions, region is how you slice."

## Notes

- **Confusing fact vs. dimension:** A fact is typically additive (salary_year_avg, job_count); a dimension is descriptive (location, job_type). If you can't sum it meaningfully across time, it's probably a dimension.
- **Slowly Changing Dimensions (SCD):** In Kimball, when a company's region changes, you version the dimension record. Inmon normalizes it away. Know your SCD strategy or your historical analysis breaks.
- **Bridges and conformed dimensions:** Multiple fact tables should share the same dimension (e.g., dim_location used by both job_postings and applicant_fact). This is how Kimball scales without duplication.
- **Revisit:** Fact table granularity matters hugely—is one row = one job posting, or one row = one application per posting? Wrong choice breaks aggregation logic.
- **Adjacent:** Data vault (hub-and-spoke) is a third approach; it splits Inmon normalization from Kimball usability but adds complexity. Consider only if you have multiple data sources or strict audit requirements.
