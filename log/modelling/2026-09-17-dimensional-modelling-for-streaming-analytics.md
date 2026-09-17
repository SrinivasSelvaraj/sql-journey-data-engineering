---
date: 2026-09-17
phase: modelling
topic: Dimensional modelling for streaming analytics
---

# Dimensional modelling for streaming analytics

*Data modelling and warehousing*

## Concept

Dimensional modelling for streaming analytics applies star schema principles to real-time data pipelines. Instead of a single denormalized table, you separate slowly-changing dimensions (job titles, locations, companies) from fast-moving facts (postings, applications, salary offers). This matters because streaming systems ingest data continuously—denormalized tables become inconsistent when you try to update historical records, and queries bloat with redundant columns that change at different rates.

Without dimensional separation, you face two problems: either you duplicate dimension data across every fact record (wasting storage and making updates dangerous), or you keep dimensions separate but force every query to join multiple tables. In streaming contexts, the first approach breaks because you can't atomically update a fact row's dimension attributes after it's been published downstream. The second approach creates operational friction—analysts write complex joins instead of self-service queries.

The solution is to design fact tables narrowly (only measures and dimension keys) and maintain dimensions independently with slowly-changing dimension (SCD) logic. For streaming, SCD Type 2 (adding new rows with validity dates) works better than Type 1 (overwriting) because you preserve audit trails and can join facts to the correct dimension version based on when the fact occurred.

## Practice

**Problem:** You have `job_postings_fact` as a single table. Analysts query it for trends: "show average salary by location and job title over time." But location names change (consolidation, data cleaning), and job titles are recoded. When you update the fact table, historical records change retroactively, making audit queries unreliable. Also, the table has 50+ columns because every dimension attribute is denormalized.

**Solution:**

```sql
-- Create dimension tables
CREATE TABLE job_title_dim (
  job_title_key INT PRIMARY KEY,
  job_title_short VARCHAR,
  job_title_category VARCHAR,
  dbt_valid_from TIMESTAMP,
  dbt_valid_to TIMESTAMP,
  is_current BOOLEAN
);

CREATE TABLE location_dim (
  location_key INT PRIMARY KEY,
  location_name VARCHAR,
  region VARCHAR,
  country VARCHAR,
  dbt_valid_from TIMESTAMP,
  dbt_valid_to TIMESTAMP,
  is_current BOOLEAN
);

-- Refactored fact table (narrow, immutable)
CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_key INT REFERENCES job_title_dim,
  location_key INT REFERENCES location_dim,
  salary_year_avg DECIMAL,
  job_work_from_home BOOLEAN,
  job_posted_date DATE
);

-- Self-service query now works reliably
SELECT
  jt.job_title_short,
  l.region,
  AVG(jpf.salary_year_avg) AS avg_salary,
  COUNT(*) AS posting_count
FROM job_postings_fact jpf
JOIN job_title_dim jt ON jpf.job_title_key = jt.job_title_key 
  AND jt.is_current = TRUE
JOIN location_dim l ON jpf.location_key = l.location_key 
  AND l.is_current = TRUE
WHERE jpf.job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY
GROUP BY jt.job_title_short, l.region;
```

## Notes

- **SCD Type 2 is non-negotiable for streaming**: Type 1 (overwrite) corrupts historical analysis. Use `dbt_valid_from`, `dbt_valid_to`, and `is_current` flags to version dimension records. Update the `is_current` flag on old records when new ones arrive.

- **Fact tables must be append-only**: In streaming, treat facts as immutable events. Never update a fact row after it's published to Kafka or your data lake. If a correction arrives, insert a new fact with a different job_id or add a `is_corrected` flag, then document it.

- **Grain mismatches break joins**: Define fact table grain early (one row per job posting, not per application or salary snapshot). If you need multiple grains (postings + applications), create separate fact tables—`job_postings_fact` and `job_applications_fact`—with their own dimension keys.

- **Conformed dimensions enable federation**: If your org has multiple fact tables (job postings, recruiter activity, candidate profiles), use the same dimension keys and SCD logic across teams. This lets analysts join across domains without asking you for reconciliation logic.

- **Revisit cardinality and drill-down depth**: A dimension with 10K values (e.g., exact location strings) can create performance issues in streaming aggregations. Group low-cardinality attributes (region, country) into the dimension table and pre-aggregate high-cardinality ones (exact address) in a separate lookup or skip them from the star schema entirely.
